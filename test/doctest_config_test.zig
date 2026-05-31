const std = @import("std");
const zentinel = @import("zentinel");
const dc = zentinel.doctest_command;
const dreport = zentinel.doctest.report;
const runner = zentinel.doctest.runner;
const case_mod = zentinel.doctest.case;
const normalizer = zentinel.doctest.normalizer;
const workspace = zentinel.doctest.workspace;
const proc = zentinel.runner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const exp_diag_snapshot = @embedFile("fixtures/doctest/config/experimental.diagnostic.txt");

// Config doctests never spawn a process or materialize a workspace.
const NoExec = struct {
    fn run(ctx: *anyopaque, argv: []const []const u8) proc.RawOutcome {
        _ = ctx;
        _ = argv;
        return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
    }
};
const NoProv = struct {
    fn m(ctx: *anyopaque, plan: workspace.Plan) workspace.MaterializeError!void {
        _ = ctx;
        _ = plan;
    }
};

fn deps() dc.Deps {
    return .{
        .executor = .{ .ctx = undefined, .runFn = NoExec.run },
        .provider = .{ .ctx = undefined, .materializeFn = NoProv.m },
    };
}

fn obs() dc.Observation {
    return .{ .run_id = "doctest_run_test", .started_at = "2026-05-31T00:00:00Z", .zentinel_version = "0.0.0", .zig_version = "0.16.0", .project_root = ".", .command = "zentinel doctest" };
}

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn runFile(a: std.mem.Allocator, path: []const u8) !dc.Output {
    const src = try readFixture(a, path);
    return dc.run(a, .{ .file = path }, path, src, obs(), deps());
}

test "minimal config example is an executable passing doctest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/config/minimal.md");
    try expectEqual(@as(usize, 1), out.report.cases.len);
    try expectEqual(dreport.CaseKind.config, out.report.cases[0].kind);
    try expectEqual(dreport.Status.passed, out.report.cases[0].status);
    try expectEqual(@as(u8, 0), out.exit_code);
    // The report identifies the config case by doc path and line.
    try expectEqualStrings("test/fixtures/doctest/config/minimal.md", out.report.cases[0].file);
    try expect(out.report.cases[0].line_start >= 1);
}

test "full config example is an executable passing doctest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/config/full.md");
    try expectEqual(@as(usize, 1), out.report.cases.len);
    try expectEqual(dreport.CaseKind.config, out.report.cases[0].kind);
    try expectEqual(dreport.Status.passed, out.report.cases[0].status);
}

test "experimental backend config_fail passes for the documented diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/config/experimental.md");
    try expectEqual(@as(usize, 1), out.report.cases.len);
    try expectEqual(dreport.CaseKind.config_fail, out.report.cases[0].kind);
    try expectEqual(dreport.Status.passed, out.report.cases[0].status);
    try expectEqual(@as(u8, 0), out.exit_code);
}

test "unknown key config_fail passes for the documented diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/config/unknown_key.md");
    try expectEqual(@as(usize, 1), out.report.cases.len);
    try expectEqual(dreport.CaseKind.config_fail, out.report.cases[0].kind);
    try expectEqual(dreport.Status.passed, out.report.cases[0].status);
}

test "config_fail with the wrong documented diagnostic fails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "test/fixtures/doctest/config/wrong_diagnostic.md");
    try expectEqual(@as(usize, 1), out.report.cases.len);
    try expectEqual(dreport.Status.failed, out.report.cases[0].status);
    try expectEqual(@as(u8, 1), out.exit_code);
}

test "docs/CONFIG_SPEC.md config examples all execute and pass" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try runFile(a, "docs/CONFIG_SPEC.md");
    // At least the minimal + full config and the two config_fail examples.
    try expect(out.report.cases.len >= 4);
    for (out.report.cases) |c| {
        try expect(c.kind == .config or c.kind == .config_fail);
        try expectEqual(dreport.Status.passed, c.status);
        try expect(std.mem.startsWith(u8, c.source_ref, "docs/CONFIG_SPEC.md:"));
    }
    try expectEqual(@as(u8, 0), out.exit_code);
}

fn configCase(kind: case_mod.CaseKind) case_mod.Case {
    return .{
        .id = "dt_cfg",
        .file = "doc.md",
        .kind = kind,
        .label = null,
        .source_ref = "doc.md:1",
        .block_refs = &.{"doc.md:1"},
        .line_start = 1,
        .line_end = 3,
        .anchor_line = 1,
    };
}

fn runConfigContent(a: std.mem.Allocator, kind: case_mod.CaseKind, content: []const u8) !runner.CaseResult {
    const ctx = runner.Context{ .arena = a, .root = ".", .zig_version = "0.16.0", .executor = .{ .ctx = undefined, .runFn = NoExec.run }, .provider = .{ .ctx = undefined, .materializeFn = NoProv.m } };
    return runner.runCase(ctx, configCase(kind), content);
}

test "config-fail diagnostic normalization snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cr = try runConfigContent(a, .config_fail, "[backend]\ndefault = \"zir\"\n");
    try expectEqual(runner.Status.passed, cr.status); // fails as expected
    const normalized = try normalizer.normalize(a, cr.stdout_excerpt, .{});
    try expectEqualStrings(exp_diag_snapshot, normalized);
}

test "property: invalid config diagnostics are deterministic for repeated runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r1 = try runConfigContent(a, .config_fail, "[project]\nbogus = \"x\"\n");
    const r2 = try runConfigContent(a, .config_fail, "[project]\nbogus = \"x\"\n");
    try expectEqualStrings(r1.stdout_excerpt, r2.stdout_excerpt);
    try expect(std.mem.indexOf(u8, r1.stdout_excerpt, "ZNTL_CONFIG_UNKNOWN_KEY") != null);
}

test "property: reordered independent config sections validate equivalently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const order_a = "[project]\nname = \"example\"\n\n[test]\ncommands = [\"zig build test\"]\n";
    const order_b = "[test]\ncommands = [\"zig build test\"]\n\n[project]\nname = \"example\"\n";
    const ra = try runConfigContent(a, .config, order_a);
    const rb = try runConfigContent(a, .config, order_b);
    try expectEqual(runner.Status.passed, ra.status);
    try expectEqual(runner.Status.passed, rb.status);
    try expectEqual(ra.status, rb.status);
}

test "property: config diagnostic normalization keeps project-relative paths stable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A config diagnostic carries section/key references, never volatile paths;
    // normalization is therefore idempotent and stable.
    const cr = try runConfigContent(a, .config_fail, "[backend]\ndefault = \"zir\"\n");
    const n1 = try normalizer.normalize(a, cr.stdout_excerpt, .{});
    const n2 = try normalizer.normalize(a, n1, .{});
    try expectEqualStrings(n1, n2);
}
