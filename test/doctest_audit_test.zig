// Cluster: doctest audit fixes.
//
// Covers the shared `file:line[:label]` ref parser (case.lineOfRef /
// case.labelOfRef) that replaced four hand-rolled accumulators [L5], and the
// label-aware `--case` selector that no longer silently ignores a `:label`
// suffix [C10].
const std = @import("std");
const zentinel = @import("zentinel");
const dc = zentinel.doctest_command;
const dcase = zentinel.doctest.case;
const workspace = zentinel.doctest.workspace;
const proc = zentinel.runner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// ----- [L5] shared ref parsing: case.lineOfRef / case.labelOfRef -----

test "case.lineOfRef parses the digit run after the first colon" {
    try expectEqual(@as(u32, 42), dcase.lineOfRef("docs/x.md:42"));
    try expectEqual(@as(u32, 7), dcase.lineOfRef("a:7:label"));
    // A label containing further colons does not affect the parsed line.
    try expectEqual(@as(u32, 3), dcase.lineOfRef("a.md:3:weird:label:with:colons"));
}

test "case.lineOfRef resolves malformed / overflowing refs to line 0, never panicking" {
    try expectEqual(@as(u32, 0), dcase.lineOfRef("nodigits"));
    try expectEqual(@as(u32, 0), dcase.lineOfRef("x:"));
    try expectEqual(@as(u32, 0), dcase.lineOfRef("x:abc"));
    // Boundary: exactly maxInt(u32) parses; one past it (and an absurdly long run)
    // resolve to 0 via the checked parseInt rather than overflowing an `n*10+d`.
    try expectEqual(@as(u32, 4294967295), dcase.lineOfRef("x:4294967295"));
    try expectEqual(@as(u32, 0), dcase.lineOfRef("x:4294967296"));
    try expectEqual(@as(u32, 0), dcase.lineOfRef("x:999999999999999999999"));
}

test "case.labelOfRef extracts the segment after the second colon, or null" {
    try expectEqual(@as(?[]const u8, null), dcase.labelOfRef("a.md:42"));
    try expectEqual(@as(?[]const u8, null), dcase.labelOfRef("no-colon"));
    // A trailing empty segment is treated as no label.
    try expectEqual(@as(?[]const u8, null), dcase.labelOfRef("a.md:42:"));
    try expectEqualStrings("alpha", dcase.labelOfRef("a.md:42:alpha").?);
    // A label may itself contain colons (everything after the 2nd colon is kept).
    try expectEqualStrings("ns:beta", dcase.labelOfRef("a.md:42:ns:beta").?);
}

test "mutator_doctest.lineOfRef delegates to the shared helper (same results)" {
    const md = zentinel.doctest.mutator_doctest;
    try expectEqual(dcase.lineOfRef("docs/x.md:42"), md.lineOfRef("docs/x.md:42"));
    try expectEqual(dcase.lineOfRef("x:4294967296"), md.lineOfRef("x:4294967296"));
    try expectEqual(@as(u32, 0), md.lineOfRef("x:999999999999"));
}

// ----- [C10] label-aware `--case` selector -----
//
// Minimal self-contained harness (mirrors test/doctest_cli_command_test.zig) so
// this file does not depend on another test file's private helpers.

const MockExec = struct {
    fn run(ctx: *anyopaque, argv: []const []const u8) proc.RawOutcome {
        _ = ctx;
        const out = struct {
            fn r(s: []const u8) proc.RawOutcome {
                return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = s, .stderr = "" };
            }
        }.r;
        if (argv.len >= 2 and std.mem.eql(u8, argv[1], "version")) return out("zentinel 0.0.0\nzig 0.16.0\n");
        if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--help")) return out("zentinel - mutation testing\nUsage: zentinel <command>\n");
        return out("");
    }
};

const MockProvider = struct {
    fn materialize(ctx: *anyopaque, plan: workspace.Plan) workspace.MaterializeError!void {
        _ = ctx;
        _ = plan;
    }
};

fn deps() dc.Deps {
    return .{
        .executor = .{ .ctx = undefined, .runFn = MockExec.run },
        .provider = .{ .ctx = undefined, .materializeFn = MockProvider.materialize },
    };
}

fn obs() dc.Observation {
    return .{
        .run_id = "doctest_run_test",
        .started_at = "2026-05-31T00:00:00Z",
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .project_root = ".",
        .command = "zentinel doctest",
    };
}

const labeled_fixture = "test/fixtures/doctest/cli/select_labeled.md";

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn runWith(a: std.mem.Allocator, options: dc.Options) !dc.Output {
    const src = try readFixture(a, labeled_fixture);
    return dc.run(a, options, labeled_fixture, src, obs(), deps());
}

test "[C10] --case file:line:label resolves the case only when the label matches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Discover the two labeled cases and their anchor lines.
    const all = try runWith(a, .{ .file = labeled_fixture });
    try expectEqual(@as(usize, 2), all.report.cases.len);

    var alpha: ?zentinel.doctest.report.Case = null;
    var beta: ?zentinel.doctest.report.Case = null;
    for (all.report.cases) |c| {
        if (std.mem.indexOf(u8, c.source_ref, ":alpha") != null) alpha = c;
        if (std.mem.indexOf(u8, c.source_ref, ":beta") != null) beta = c;
    }
    try expect(alpha != null);
    try expect(beta != null);

    // Correct label resolves exactly the matching case.
    const alpha_ref = try std.fmt.allocPrint(a, "{s}:{d}:alpha", .{ labeled_fixture, alpha.?.line_start });
    const by_alpha = try runWith(a, .{ .file = labeled_fixture, .case_ref = alpha_ref });
    try expectEqual(@as(usize, 1), by_alpha.report.cases.len);
    try expectEqualStrings(alpha.?.id, by_alpha.report.cases[0].id);

    // Same anchor line, WRONG label: previously accepted (label ignored), now
    // rejected as CaseNotFound.
    const wrong_ref = try std.fmt.allocPrint(a, "{s}:{d}:beta", .{ labeled_fixture, alpha.?.line_start });
    const src = try readFixture(a, labeled_fixture);
    try std.testing.expectError(error.CaseNotFound, dc.run(a, .{ .file = labeled_fixture, .case_ref = wrong_ref }, labeled_fixture, src, obs(), deps()));

    // A bare `file:line` (no label suffix) still resolves the case at that line,
    // unchanged from before.
    const bare_ref = try std.fmt.allocPrint(a, "{s}:{d}", .{ labeled_fixture, beta.?.line_start });
    const by_bare = try runWith(a, .{ .file = labeled_fixture, .case_ref = bare_ref });
    try expectEqual(@as(usize, 1), by_bare.report.cases.len);
    try expectEqualStrings(beta.?.id, by_bare.report.cases[0].id);
}
