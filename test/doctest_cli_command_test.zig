const std = @import("std");
const zentinel = @import("zentinel");
const dc = zentinel.doctest_command;
const dreport = zentinel.doctest.report;
const workspace = zentinel.doctest.workspace;
const proc = zentinel.runner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const pass_report_snapshot = @embedFile("fixtures/doctest/cli/pass.report.json");

// A routing mock executor: returns canned output keyed on the zentinel subcommand.
const MockExec = struct {
    fn run(ctx: *anyopaque, argv: []const []const u8) proc.RawOutcome {
        _ = ctx;
        const out = struct {
            fn r(s: []const u8) proc.RawOutcome {
                return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = s, .stderr = "" };
            }
        }.r;
        if (argv.len >= 2 and std.mem.eql(u8, argv[1], "version")) return out("zentinel 0.0.0\nzig 0.16.0\n");
        if (argv.len >= 2 and std.mem.eql(u8, argv[1], "--help")) return out("zentinel - Zig-native mutation testing\nUsage: zentinel <command>\n");
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

fn obs(command: []const u8) dc.Observation {
    return .{
        .run_id = "doctest_run_test",
        .started_at = "2026-05-31T00:00:00Z",
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .project_root = ".",
        .command = command,
    };
}

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn runFile(a: std.mem.Allocator, path: []const u8, options: dc.Options) !dc.Output {
    const src = try readFixture(a, path);
    return dc.run(a, options, path, src, obs("zentinel doctest"), deps());
}

test "zentinel doctest --file docs/CLI_SPEC.md finds and passes the version CLI case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "docs/CLI_SPEC.md", .{ .file = "docs/CLI_SPEC.md" });
    var found = false;
    for (out.report.cases) |c| {
        if (c.kind == .cli and c.command != null and std.mem.eql(u8, c.command.?.original, "zentinel version")) {
            try expectEqual(dreport.Status.passed, c.status);
            found = true;
        }
    }
    try expect(found);
    try expectEqual(@as(u8, 0), out.exit_code);
}

test "passing CLI doctest report matches the schema snapshot and validates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/cli/pass.md", .{ .file = "test/fixtures/doctest/cli/pass.md" });
    try expectEqual(@as(u8, 0), out.exit_code);
    try expectEqual(dreport.Violation.ok, dreport.validate(out.report));
    const json = try dreport.toJson(a, out.report);
    try expectEqualStrings(pass_report_snapshot, json);
}

test "failing CLI doctest reports a failed case and exits 1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/cli/fail.md", .{ .file = "test/fixtures/doctest/cli/fail.md" });
    try expectEqual(@as(u8, 1), out.exit_code);
    try expectEqual(@as(usize, 1), out.report.cases.len);
    try expectEqual(dreport.Status.failed, out.report.cases[0].status);
    // Snapshot evidence is present and records the mismatch.
    try expect(out.report.cases[0].result != null);
    try expect(out.report.cases[0].result.?.snapshot != null);
    try expect(!out.report.cases[0].result.?.snapshot.?.matched);
}

test "invalid CLI doctest reports an invalid case with a stable diagnostic code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/cli/invalid.md", .{ .file = "test/fixtures/doctest/cli/invalid.md" });
    try expectEqual(@as(u8, 1), out.exit_code);
    try expectEqual(@as(usize, 1), out.report.cases.len);
    try expectEqual(dreport.Status.invalid, out.report.cases[0].status);
    try expectEqual(@as(usize, 1), out.report.cases[0].diagnostics.len);
    try expectEqualStrings(zentinel.doctest.runner.command_rejected_code, out.report.cases[0].diagnostics[0].code);
}

test "internal_error doctest report requires a run.error object" {
    const ok_report = dreport.Report{
        .run = .{ .id = "doctest_run_x", .status = .completed, .@"error" = null, .zentinel_version = "0.0.0", .zig_version = "0.16.0", .command = "zentinel doctest", .project_root = ".", .started_at = "<t>", .duration_ms = 0 },
        .summary = .{},
        .cases = &.{},
    };
    try expectEqual(dreport.Violation.ok, dreport.validate(ok_report));

    var bad = ok_report;
    bad.run.status = .internal_error;
    try expectEqual(dreport.Violation.internal_error_requires_error, dreport.validate(bad));
}

test "exit code is 1 for failing statuses and 0 for successful ones" {
    inline for (.{ dreport.Status.failed, dreport.Status.compile_error, dreport.Status.timeout, dreport.Status.invalid }) |st| {
        const r = oneCaseReport(st);
        try expectEqual(@as(u8, 1), dreport.exitCode(r));
    }
    inline for (.{ dreport.Status.passed, dreport.Status.expected_compile_error, dreport.Status.skipped }) |st| {
        const r = oneCaseReport(st);
        try expectEqual(@as(u8, 0), dreport.exitCode(r));
    }
}

fn oneCaseReport(status: dreport.Status) dreport.Report {
    const cases = &[_]dreport.Case{.{
        .id = "dt_x",
        .file = "doc.md",
        .line_start = 1,
        .line_end = 1,
        .source_ref = "doc.md:1",
        .block_refs = &.{"doc.md:1"},
        .kind = .cli,
        .status = status,
        .expectation = null,
        .command = null,
        .result = null,
        .diagnostics = &.{},
        .advisory = .{},
    }};
    return .{
        .run = .{ .id = "doctest_run_x", .status = .completed, .@"error" = null, .zentinel_version = "0.0.0", .zig_version = "0.16.0", .command = "zentinel doctest", .project_root = ".", .started_at = "<t>", .duration_ms = 0 },
        .summary = dreport.summarize(cases),
        .cases = cases,
    };
}

test "--case selects by durable id and by anchor-line source ref; expectation lines are rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const all = try runFile(a, "test/fixtures/doctest/cli/select.md", .{ .file = "test/fixtures/doctest/cli/select.md" });
    try expectEqual(@as(usize, 2), all.report.cases.len);
    const first = all.report.cases[0];

    // Select by durable dt_ id.
    const by_id = try runFile(a, "test/fixtures/doctest/cli/select.md", .{ .file = "test/fixtures/doctest/cli/select.md", .case_ref = first.id });
    try expectEqual(@as(usize, 1), by_id.report.cases.len);
    try expectEqualStrings(first.id, by_id.report.cases[0].id);

    // Select by anchor-line source ref.
    const anchor_ref = try std.fmt.allocPrint(a, "test/fixtures/doctest/cli/select.md:{d}", .{first.line_start});
    const by_ref = try runFile(a, "test/fixtures/doctest/cli/select.md", .{ .file = "test/fixtures/doctest/cli/select.md", .case_ref = anchor_ref });
    try expectEqual(@as(usize, 1), by_ref.report.cases.len);
    try expectEqualStrings(first.id, by_ref.report.cases[0].id);

    // A source ref pointing at the expectation block line (anchor + 4) resolves nothing.
    const exp_ref = try std.fmt.allocPrint(a, "test/fixtures/doctest/cli/select.md:{d}", .{first.line_start + 4});
    const src = try readFixture(a, "test/fixtures/doctest/cli/select.md");
    try std.testing.expectError(error.CaseNotFound, dc.run(a, .{ .file = "x", .case_ref = exp_ref }, "test/fixtures/doctest/cli/select.md", src, obs("zentinel doctest"), deps()));
}

test "--case with an out-of-range numeric ref yields CaseNotFound, not an overflow panic (M4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/doctest/cli/select.md");
    // A line number past maxInt(u32): the hand-rolled `n = n*10 + d` accumulator
    // overflowed, aborting the whole process with `panic: integer overflow`
    // (Debug/ReleaseSafe) or wrapping to a wrong line (ReleaseFast). A malformed
    // or typo'd `--case` ref must deterministically resolve to nothing (M4).
    const overflow_ref = "test/fixtures/doctest/cli/select.md:99999999999";
    try std.testing.expectError(error.CaseNotFound, dc.run(a, .{ .file = "x", .case_ref = overflow_ref }, "test/fixtures/doctest/cli/select.md", src, obs("zentinel doctest"), deps()));
}

test "property: --file selection preserves case ordering by anchor line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/cli/select.md", .{ .file = "test/fixtures/doctest/cli/select.md" });
    try expect(out.report.cases.len >= 2);
    var prev: u32 = 0;
    for (out.report.cases) |c| {
        try expect(c.line_start >= prev);
        prev = c.line_start;
    }
}

test "property: repeated runs are equivalent except normalized observation metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readFixture(a, "test/fixtures/doctest/cli/pass.md");
    const r1 = try dc.run(a, .{ .file = "x" }, "test/fixtures/doctest/cli/pass.md", src, .{ .run_id = "doctest_run_aaa", .started_at = "2026-01-01T00:00:00Z", .zentinel_version = "0.0.0", .zig_version = "0.16.0", .project_root = ".", .command = "zentinel doctest" }, deps());
    const r2 = try dc.run(a, .{ .file = "x" }, "test/fixtures/doctest/cli/pass.md", src, .{ .run_id = "doctest_run_bbb", .started_at = "2026-12-31T23:59:59Z", .zentinel_version = "0.0.0", .zig_version = "0.16.0", .project_root = ".", .command = "zentinel doctest" }, deps());
    const j1 = try dreport.normalizeForComparison(a, try dreport.toJson(a, r1.report));
    const j2 = try dreport.normalizeForComparison(a, try dreport.toJson(a, r2.report));
    try expectEqualStrings(j1, j2);
}

test "property: --no-color does not change doctest output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const colored = try runFile(a, "test/fixtures/doctest/cli/fail.md", .{ .file = "x", .no_color = false });
    const plain = try runFile(a, "test/fixtures/doctest/cli/fail.md", .{ .file = "x", .no_color = true });
    const t1 = try dc.renderText(a, colored.report);
    const t2 = try dc.renderText(a, plain.report);
    try expectEqualStrings(t1, t2);
}

test "doctest parseArgs rejects unsupported subcommands and unknown options" {
    try std.testing.expectError(error.UnsupportedSubcommand, dc.parseArgs(&.{"explain"}));
    try std.testing.expectError(error.UnknownOption, dc.parseArgs(&.{"--mutate"}));
    try std.testing.expectError(error.InvalidFormat, dc.parseArgs(&.{ "--format", "yaml" }));
    const ok = try dc.parseArgs(&.{ "--file", "docs/CLI_SPEC.md", "--format", "json", "--no-color" });
    try expectEqual(dc.Format.json, ok.format);
    try expect(ok.no_color);
}
