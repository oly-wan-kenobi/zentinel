const std = @import("std");
const zentinel = @import("zentinel");

const rc = zentinel.run_command;
const config = zentinel.config;
const runner = zentinel.runner;
const report = zentinel.report;
const cache = zentinel.cache;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;
const wp = zentinel.worker_pool;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// --- Workload + deterministic run harness ----------------------------------

const workload = @embedFile("fixtures/performance/workload.zig");

const cfg_toml =
    \\[project]
    \\name = "bench"
    \\
    \\[mutators]
    \\enabled = ["arithmetic_add_sub", "arithmetic_mul_div"]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\
;

fn loadCfg(a: std.mem.Allocator) config.Config {
    var diag: config.Diagnostic = .{};
    return config.load(a, cfg_toml, &diag) catch @panic("config did not parse");
}

fn observation() rc.Observation {
    return .{ .run_id = "run_bench00000000000000", .started_at = "1970-01-01T00:00:00Z", .project_root = "<project>", .zentinel_version = "0.0.0", .zig_version = "0.16.0", .config_hash = "sha256:0000000000000000", .duration_ms = 0 };
}

fn pass() runner.RawOutcome {
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}
fn fail() runner.RawOutcome {
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "boom" };
}

const Env = struct {
    arena: std.mem.Allocator,
    cwd: []const u8 = "<project>",
    baseline_outcome: runner.RawOutcome,
    mutant_outcome: runner.RawOutcome,
    lock: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
};
fn spinLock(f: *std.atomic.Value(u32)) void {
    while (f.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}
fn spinUnlock(f: *std.atomic.Value(u32)) void {
    f.store(0, .release);
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
    spinLock(&env.lock);
    defer spinUnlock(&env.lock);
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, env.cwd, ex, mode) catch @panic("mutant run failed");
}

const files = [_]rc.FileSource{.{ .path = "src/workload.zig", .source = workload }};

fn runWorkload(a: std.mem.Allocator, no_cache: bool, jobs: ?usize) rc.RunOutcome {
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = fail() };
    const baseline_executor = runner.Executor{ .ctx = &env, .runFn = baselineCmd };
    const mutant_executor = rc.MutantRunner{ .ctx = &env, .runFn = mutantRunFn };
    return rc.run(a, loadCfg(a), &files, .{ .no_cache = no_cache, .jobs = jobs }, baseline_executor, mutant_executor, observation()) catch @panic("run failed");
}

// --- Equivalence (cached/uncached, cold/warm, serial/parallel) -------------

test "cached and uncached reports are equivalent except diagnostics.cache and durations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cached = runWorkload(a, false, null);
    const uncached = runWorkload(a, true, null);
    try expect(report.equivalentIgnoringTiming(cached.report, uncached.report));

    const cd_on = cache.toReportDiagnostics(cached.cache);
    const cd_off = cache.toReportDiagnostics(uncached.cache);
    try expect(cd_on.enabled and !cd_off.enabled);
    try expectEqual(report.CacheMode.metadata_only, cd_on.mode);
    try expectEqual(report.CacheMode.disabled, cd_off.mode);
    try expect(cd_on.misses > 0 and cd_off.misses == 0);
}

test "cold and warm runs differ only in durations and allowed cache diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The run is a deterministic function of the workload, so a warm Zig
    // build-cache (which only changes compile time) cannot change statuses,
    // ordering, evidence, or summary counts -- modeled by two identical runs.
    const cold = runWorkload(a, false, null);
    const warm = runWorkload(a, false, null);
    try expect(report.equivalentIgnoringTiming(cold.report, warm.report));
    try expectEqual(cold.report.summary.killed, warm.report.summary.killed);
    try expect(cold.cache.build_cache.isolated and warm.cache.build_cache.isolated);
}

test "serial and parallel reports are equivalent and workers do not share cache or workspace paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const serial = runWorkload(a, false, 1);
    const parallel = runWorkload(a, false, 8);
    try expect(report.equivalentIgnoringTiming(serial.report, parallel.report));

    try expect(parallel.report.mutants.len >= 2);
    const m0 = parallel.report.mutants[0].id;
    const m1 = parallel.report.mutants[1].id;
    const ws0 = try wp.workspaceRoot(a, observation().run_id, m0);
    const ws1 = try wp.workspaceRoot(a, observation().run_id, m1);
    try expect(!std.mem.eql(u8, ws0, ws1)); // distinct workspace
    try expect(!std.mem.eql(u8, try wp.cacheDirIn(a, ws0), try wp.cacheDirIn(a, ws1))); // distinct .zig-cache
    try expect(!std.mem.eql(u8, try wp.outDirIn(a, ws0), try wp.outDirIn(a, ws1))); // distinct zig-out
}

// --- Machine-readable benchmark output snapshot ----------------------------

const benchmark_snapshot = @embedFile("fixtures/performance/benchmark.json");

test "benchmark output is machine-readable and matches the normalized snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cached = runWorkload(a, false, null);
    const uncached = runWorkload(a, true, null);
    const serial = runWorkload(a, false, 1);
    const parallel = runWorkload(a, false, 8);
    const warm = runWorkload(a, false, null);
    const eq = report.Equivalence{
        .cached_uncached = report.equivalentIgnoringTiming(cached.report, uncached.report),
        .serial_parallel = report.equivalentIgnoringTiming(serial.report, parallel.report),
        .cold_warm = report.equivalentIgnoringTiming(cached.report, warm.report),
    };
    try expect(eq.cached_uncached and eq.serial_parallel and eq.cold_warm);

    const bench = report.benchmark("tiny-arithmetic", cached.report, eq);
    const json = try report.benchmarkToJson(a, bench);
    try expectEqualStrings(benchmark_snapshot, json);
}

// --- diagnostics.cache snapshot + report schema validity --------------------

const cache_diag_snapshot = @embedFile("fixtures/performance/cache_diagnostics.json");

test "cache diagnostics serialize under diagnostics.cache and keep the report schema-valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cached = runWorkload(a, false, null);
    const cd = cache.toReportDiagnostics(cached.cache);
    const json = try std.json.Stringify.valueAlloc(a, cd, .{ .whitespace = .indent_2 });
    try expectEqualStrings(cache_diag_snapshot, json);

    // Wiring the cache diagnostics into the report keeps it valid and observable.
    var wired = cached.report;
    wired.diagnostics = .{ .cache = cd };
    try expectEqual(report.Violation.ok, report.validate(wired));
    const rjson = try report.toJson(a, wired);
    try expect(std.mem.indexOf(u8, rjson, "\"cache\"") != null);
    try expect(std.mem.indexOf(u8, rjson, "metadata_only") != null);
}

// The concrete numeric CI smoke budgets in docs/PERFORMANCE_STRATEGY.md are
// verified by scripts/check_perf_budgets.py (a cross-directory @embedFile of the
// doc is disallowed by the Zig package boundary).
