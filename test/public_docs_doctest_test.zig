const std = @import("std");
const zentinel = @import("zentinel");
const dc = zentinel.doctest_command;
const dreport = zentinel.doctest.report;
const workspace = zentinel.doctest.workspace;
const proc = zentinel.runner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// Canned, deterministic command outputs. Public docs execute through the doctest
// engine with an injected executor; these are the documented outputs the
// expectation blocks are validated against (JSON examples are checked as a
// supported subset).
const report_json =
    \\{
    \\  "schema_version": "zentinel.report.v1",
    \\  "run": { "id": "run_doctest", "status": "completed" },
    \\  "summary": { "total": 0 }
    \\}
;
const ai_doctest_suggest_json =
    \\{
    \\  "schema_version": "zentinel.ai.doctest.suggest.response.v1",
    \\  "flow": "suggest_doctest",
    \\  "suggestions": []
    \\}
;

const MockExec = struct {
    fn run(ctx: *anyopaque, argv: []const []const u8) proc.RawOutcome {
        _ = ctx;
        const out = struct {
            fn r(s: []const u8) proc.RawOutcome {
                return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = s, .stderr = "" };
            }
        }.r;
        if (argv.len >= 2 and std.mem.eql(u8, argv[1], "version")) return out("zentinel 0.0.0\nzig 0.16.0\n");
        if (argv.len >= 2 and (std.mem.eql(u8, argv[1], "--help") or std.mem.eql(u8, argv[1], "-h")))
            return out("zentinel - Zig-native mutation testing\nUsage: zentinel <command>\n");
        if (argv.len >= 3 and std.mem.eql(u8, argv[1], "doctest") and std.mem.eql(u8, argv[2], "suggest"))
            return out(ai_doctest_suggest_json);
        if (argv.len >= 2 and std.mem.eql(u8, argv[1], "run")) return out(report_json);
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
        .run_id = "doctest_run_public",
        .started_at = "2026-05-31T00:00:00Z",
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .project_root = ".",
        .command = "zentinel doctest",
    };
}

fn readFile(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn runFile(a: std.mem.Allocator, path: []const u8) !dc.Output {
    const src = try readFile(a, path);
    return dc.run(a, .{ .file = path }, path, src, obs(), deps());
}

/// True if `path` produces at least one passing case of `kind` whose command (if
/// any) contains `needle`.
fn hasPassingCase(a: std.mem.Allocator, path: []const u8, kind: dreport.CaseKind, needle: []const u8) !bool {
    const out = try runFile(a, path);
    for (out.report.cases) |c| {
        if (c.kind != kind) continue;
        if (c.status != .passed) continue;
        if (needle.len == 0) return true;
        if (c.command) |cmd| {
            if (std.mem.indexOf(u8, cmd.original, needle) != null) return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Coverage fixtures: each required public-doc example kind executes and passes.
// ---------------------------------------------------------------------------
test "public CLI example executes through doctest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try hasPassingCase(a, "test/fixtures/doctest/public_docs/cli.md", .cli, "zentinel version"));
}

test "public config example executes through doctest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try hasPassingCase(a, "test/fixtures/doctest/public_docs/config.md", .config, ""));
}

test "public report JSON example validates as a supported subset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try hasPassingCase(a, "test/fixtures/doctest/public_docs/report_json.md", .cli, "zentinel run --report json"));
}

test "public doctest AI JSON example validates as a supported subset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try hasPassingCase(a, "test/fixtures/doctest/public_docs/doctest_ai_json.md", .cli, "zentinel doctest suggest"));
}

// ---------------------------------------------------------------------------
// The selected real public contract docs execute through doctest.
// ---------------------------------------------------------------------------
test "docs/CLI_SPEC.md has a passing CLI doctest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try hasPassingCase(a, "docs/CLI_SPEC.md", .cli, "zentinel version"));
}

test "docs/CONFIG_SPEC.md has a passing config doctest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try hasPassingCase(a, "docs/CONFIG_SPEC.md", .config, ""));
}

test "docs/REPORT_FORMAT.md has a passing report JSON doctest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try hasPassingCase(a, "docs/REPORT_FORMAT.md", .cli, "zentinel run"));
}

test "docs/DOCTEST_AI_INTEGRATION.md has a passing doctest AI JSON doctest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try hasPassingCase(a, "docs/DOCTEST_AI_INTEGRATION.md", .cli, "zentinel doctest suggest"));
}

// ---------------------------------------------------------------------------
// Verifier artifacts reference public-docs doctest evidence.
// ---------------------------------------------------------------------------
test "verifier artifact references public-docs doctest evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try readFile(a, "test/fixtures/doctest/public_docs/verification.json");
    const v = try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{});
    const stages = v.object.get("stages").?.array;
    var found = false;
    for (stages.items) |s| {
        const artifact = s.object.get("artifact") orelse continue;
        if (artifact == .string and std.mem.endsWith(u8, artifact.string, "doctest/report.json")) found = true;
    }
    try expect(found);
}
