const std = @import("std");
const zentinel = @import("zentinel");

const config = zentinel.config;
const rc = zentinel.run_command;
const report = zentinel.report;
const runner = zentinel.runner;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFile(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

test "dogfood config parses and targets the mutation fixtures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = try readFile(a, "zentinel.dogfood.toml");
    var diag: config.Diagnostic = .{};
    const cfg = try config.load(a, bytes, &diag);

    try expectEqualStrings("dogfood", cfg.project_name);
    try expectEqualStrings("src/**/*.zig", cfg.include[0]);
    try expectEqual(@as(usize, 1), cfg.test_commands.len);
    try expectEqualStrings("zig test src/calc.zig", cfg.test_commands[0]);
    try expectEqualStrings("zig-out/zentinel-dogfood", cfg.report_output_dir);
    // The dogfood targets Phase 1 operators present in the fixture.
    var has_add_sub = false;
    var has_boundary = false;
    for (cfg.mutators_enabled) |op| {
        if (std.mem.eql(u8, op, "arithmetic_add_sub")) has_add_sub = true;
        if (std.mem.eql(u8, op, "comparison_boundary")) has_boundary = true;
    }
    try expect(has_add_sub and has_boundary);
}

// --- Deterministic dogfood harness (mock executors) ------------------------

const Env = struct {
    arena: std.mem.Allocator,
    baseline_outcome: runner.RawOutcome,
    mutant_outcome: runner.RawOutcome,
};

fn ok() runner.RawOutcome {
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}
fn fail() runner.RawOutcome {
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "fail" };
}

fn baselineCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    return @as(*Env, @ptrCast(@alignCast(ctx))).baseline_outcome;
}
fn mutantCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    return @as(*Env, @ptrCast(@alignCast(ctx))).mutant_outcome;
}
fn mutantRunFn(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *Env = @ptrCast(@alignCast(ctx));
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, "<project>", ex, mode) catch @panic("mutant run failed");
}

fn dogfoodObservation(run_id: []const u8, started_at: []const u8, duration_ms: u64) rc.Observation {
    return .{
        .run_id = run_id,
        .started_at = started_at,
        .project_root = "<project>",
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .config_hash = "sha256:dogfood",
        .zig_cache_namespace = ".zig-cache/zentinel/workspaces",
        .duration_ms = duration_ms,
    };
}

test "two fixture dogfood runs produce equivalent normalized reports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cfg_bytes = try readFile(a, "zentinel.dogfood.toml");
    var diag: config.Diagnostic = .{};
    const cfg = try config.load(a, cfg_bytes, &diag);

    const source = try readFile(a, "test/fixtures/dogfood/sample/src/calc.zig");
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = source }};

    var env = Env{ .arena = a, .baseline_outcome = ok(), .mutant_outcome = fail() };
    const baseline_executor = runner.Executor{ .ctx = &env, .runFn = baselineCmd };
    const mutant_executor = rc.MutantRunner{ .ctx = &env, .runFn = mutantRunFn };

    // Two runs that differ ONLY in observation metadata (run id, timestamp,
    // duration). After normalization those fields collapse, so the reports must
    // be byte-identical — the dogfood is deterministic.
    const run1 = try rc.run(a, cfg, &files, .{}, baseline_executor, mutant_executor, dogfoodObservation("run_aaaaaaaa", "2026-01-01T00:00:00Z", 5));
    const run2 = try rc.run(a, cfg, &files, .{}, baseline_executor, mutant_executor, dogfoodObservation("run_bbbbbbbb", "2026-02-02T02:02:02Z", 99));

    // The fixture has two Phase 1 candidates (arithmetic_add_sub, comparison_boundary).
    try expectEqual(@as(usize, 2), run1.report.mutants.len);
    try expectEqual(report.RunStatus.completed, run1.report.run.status);

    const norm1 = try report.normalizeForComparison(a, try report.toJson(a, run1.report));
    const norm2 = try report.normalizeForComparison(a, try report.toJson(a, run2.report));
    try expectEqualStrings(norm1, norm2);
}
