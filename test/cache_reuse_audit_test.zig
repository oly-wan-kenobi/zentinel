// Audit for [M1]: read-side result-cache reuse. These tests inject an in-memory
// content-addressed result store into `run_command.run` and prove:
//   * a second run over identical inputs serves every cacheable mutant from the
//     store and SKIPS compile+test (the mutant runner is never invoked), while
//     producing a report equivalent to the first run (report-equivalence);
//   * `--no-cache` (and a disabled `cache.enabled`) disables reuse even with a
//     store wired;
//   * a changed source / config / test command yields a cache MISS (the key is
//     content-addressed, so reuse is never served across a changed input);
//   * the report's `diagnostics.cache.hits`/`misses` reflect real reuse.
//
// The mutant runner goes through the real `mutant_runner.run` (real patch
// validation + classification) over a mock command executor, so a served hit is
// checked against a genuinely-classified verdict, not a stubbed status.
const std = @import("std");
const zentinel = @import("zentinel");

const rc = zentinel.run_command;
const config = zentinel.config;
const runner = zentinel.runner;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;
const report = zentinel.report;
const cache = zentinel.cache;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// --- Fixtures --------------------------------------------------------------

const calc_src = "pub fn add(a: i32, b: i32) i32 {\n    return a + b;\n}\n";
const calc_src_changed = "pub fn add(a: i32, b: i32) i32 {\n    return a + b + 0;\n}\n";

const cfg_toml =
    \\[project]
    \\name = "sample"
    \\
    \\[mutators]
    \\enabled = ["arithmetic_add_sub", "arithmetic_mul_div"]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\
;

const cfg_toml_other_command =
    \\[project]
    \\name = "sample"
    \\
    \\[mutators]
    \\enabled = ["arithmetic_add_sub", "arithmetic_mul_div"]
    \\
    \\[test]
    \\commands = ["zig build test -Dother"]
    \\
;

fn loadCfg(a: std.mem.Allocator, toml: []const u8) config.Config {
    var diag: config.Diagnostic = .{};
    return config.load(a, toml, &diag) catch @panic("config did not parse");
}

fn observation() rc.Observation {
    return .{
        .run_id = "run_testfixture00000000",
        .started_at = "1970-01-01T00:00:00Z",
        .project_root = "<project>",
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .config_hash = "sha256:0000000000000000",
        .duration_ms = 0,
    };
}

// --- Mock executor + run-counting mutant runner ----------------------------

fn pass() runner.RawOutcome {
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}
fn failure() runner.RawOutcome {
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "test failed" };
}

const Env = struct {
    arena: std.mem.Allocator,
    cwd: []const u8 = "<project>",
    baseline_outcome: runner.RawOutcome,
    mutant_outcome: runner.RawOutcome,
    /// How many times the mutant runner actually executed a mutant. A reuse hit
    /// must NOT increment this -- that is the observable proof compile+test was
    /// skipped. Atomic so the counter is sound even if a run uses >1 worker.
    runs: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    lock: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
};

fn spinLock(flag: *std.atomic.Value(u32)) void {
    while (flag.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}
fn spinUnlock(flag: *std.atomic.Value(u32)) void {
    flag.store(0, .release);
}

fn mutantCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    return @as(*Env, @ptrCast(@alignCast(ctx))).mutant_outcome;
}
fn baselineCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    return @as(*Env, @ptrCast(@alignCast(ctx))).baseline_outcome;
}
fn mutantRunFn(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *Env = @ptrCast(@alignCast(ctx));
    spinLock(&env.lock);
    defer spinUnlock(&env.lock);
    _ = env.runs.fetchAdd(1, .monotonic);
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, env.cwd, ex, mode) catch @panic("mutant run failed");
}

fn baselineExecutor(env: *Env) runner.Executor {
    return .{ .ctx = env, .runFn = baselineCmd };
}
fn mutantRunner(env: *Env) rc.MutantRunner {
    return .{ .ctx = env, .runFn = mutantRunFn };
}

// --- In-memory result store ------------------------------------------------

/// A minimal content-addressed store backing `rc.ResultStore`. Bytes are copied
/// into the arena so an entry outlives the run that wrote it (the production
/// store persists to disk; this models the same cross-run lifetime).
const MemStore = struct {
    arena: std.mem.Allocator,
    map: std.StringHashMap([]const u8),
    gets: usize = 0,
    puts: usize = 0,

    fn init(a: std.mem.Allocator) MemStore {
        return .{ .arena = a, .map = std.StringHashMap([]const u8).init(a) };
    }

    fn getFn(ctx: *anyopaque, key: []const u8) ?[]const u8 {
        const self: *MemStore = @ptrCast(@alignCast(ctx));
        self.gets += 1;
        return self.map.get(key);
    }
    fn putFn(ctx: *anyopaque, key: []const u8, bytes: []const u8) void {
        const self: *MemStore = @ptrCast(@alignCast(ctx));
        self.puts += 1;
        const k = self.arena.dupe(u8, key) catch @panic("oom");
        const v = self.arena.dupe(u8, bytes) catch @panic("oom");
        self.map.put(k, v) catch @panic("oom");
    }
    fn store(self: *MemStore) rc.ResultStore {
        return .{ .ctx = self, .getFn = getFn, .putFn = putFn };
    }
    fn count(self: *const MemStore) usize {
        return self.map.count();
    }
};

fn files(src: []const u8) [1]rc.FileSource {
    return [_]rc.FileSource{.{ .path = "src/calc.zig", .source = src }};
}

// --- Tests -----------------------------------------------------------------

test "a second run over identical inputs serves every mutant from the store and skips compile+test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var mem = MemStore.init(a);
    const fs = files(calc_src);

    // Run 1: cold store. Every cacheable mutant is computed and persisted.
    var env1 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const first = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env1), mutantRunner(&env1), observation());
    const ran_first = env1.runs.load(.monotonic);
    try expect(ran_first > 0); // mutants actually executed
    try expect(mem.puts > 0); // verdicts persisted
    try expect(mem.count() == first.report.summary.killed + first.report.summary.survived + first.report.summary.compile_error);

    // Run 2: warm store, identical inputs. No mutant is executed; every cacheable
    // verdict is served, and the report is equivalent to run 1 (report-equivalence).
    var env2 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const second = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env2), mutantRunner(&env2), observation());
    try expectEqual(@as(usize, 0), env2.runs.load(.monotonic)); // compile+test SKIPPED on every mutant
    try expect(report.equivalentIgnoringTiming(first.report, second.report));

    // Reuse is observable in the run cache metadata and the report diagnostics.
    try expectEqual(report.CacheMode.read_write, second.cache.mode);
    try expect(second.cache.enabled);
    const diag = cache.toReportDiagnostics(second.cache);
    try expect(diag.hits > 0);
    try expectEqual(@as(u64, 0), diag.misses); // all served
    try expectEqual(diag.hits, @as(u64, @intCast(second.cache.result_keys.len)));
}

test "a hit reproduces the same report a fresh storeless run produces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var mem = MemStore.init(a);
    const fs = files(calc_src);

    // Storeless reference run (reuse disabled: no store wired).
    var env_ref = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const reference = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{}, baselineExecutor(&env_ref), mutantRunner(&env_ref), observation());

    // Prime, then serve.
    var env_prime = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env_prime), mutantRunner(&env_prime), observation());
    var env_served = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const served = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env_served), mutantRunner(&env_served), observation());

    try expectEqual(@as(usize, 0), env_served.runs.load(.monotonic));
    // A served hit yields a report equivalent to one computed without any cache:
    // the cache only skips recomputation, it never changes a verdict.
    try expect(report.equivalentIgnoringTiming(reference.report, served.report));
}

test "--no-cache disables reuse even when a store is wired" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var mem = MemStore.init(a);
    const fs = files(calc_src);

    // Prime the store with a normal cached run.
    var env_prime = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env_prime), mutantRunner(&env_prime), observation());
    try expect(mem.count() > 0);
    const puts_before = mem.puts;

    // --no-cache: the wired store must be ignored -- mutants run again, nothing is
    // read or written, and the cache reports as disabled with no keys.
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const out = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store(), .no_cache = true }, baselineExecutor(&env), mutantRunner(&env), observation());
    try expect(env.runs.load(.monotonic) > 0); // not served
    try expectEqual(puts_before, mem.puts); // nothing persisted under --no-cache
    try expectEqual(report.CacheMode.disabled, out.cache.mode);
    try expect(!out.cache.enabled);
    try expectEqual(@as(usize, 0), out.cache.result_keys.len);
    const diag = cache.toReportDiagnostics(out.cache);
    try expectEqual(@as(u64, 0), diag.hits);
    try expectEqual(@as(u64, 0), diag.misses);
}

test "cache.enabled=false disables reuse like --no-cache" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var mem = MemStore.init(a);
    const fs = files(calc_src);

    // Prime under the default (enabled) config.
    var env_prime = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env_prime), mutantRunner(&env_prime), observation());

    const cfg_disabled =
        \\[project]
        \\name = "sample"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub", "arithmetic_mul_div"]
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
        \\[cache]
        \\enabled = false
        \\
    ;
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const out = try rc.run(a, loadCfg(a, cfg_disabled), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env), mutantRunner(&env), observation());
    try expect(env.runs.load(.monotonic) > 0); // not served
    try expectEqual(report.CacheMode.disabled, out.cache.mode);
}

test "a changed source produces a miss and re-runs the mutant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var mem = MemStore.init(a);

    // Prime over the original source.
    const fs1 = files(calc_src);
    var env1 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml), &fs1, .{ .result_cache = mem.store() }, baselineExecutor(&env1), mutantRunner(&env1), observation());
    const keys_after_first = mem.count();
    try expect(keys_after_first > 0);

    // The changed source hashes differently, so every key changes: a miss, the
    // mutants run again, and NEW entries are written (none of the originals served).
    const fs2 = files(calc_src_changed);
    var env2 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml), &fs2, .{ .result_cache = mem.store() }, baselineExecutor(&env2), mutantRunner(&env2), observation());
    try expect(env2.runs.load(.monotonic) > 0); // recomputed, not served
    try expect(mem.count() > keys_after_first); // distinct keys persisted
}

test "a changed test command produces a miss" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var mem = MemStore.init(a);
    const fs = files(calc_src);

    // Prime with the configured suite "zig build test".
    var env1 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env1), mutantRunner(&env1), observation());
    const keys_after_first = mem.count();

    // A different configured command changes both the executed and configured key
    // fields, so the same mutants miss and re-run.
    var env2 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml_other_command), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env2), mutantRunner(&env2), observation());
    try expect(env2.runs.load(.monotonic) > 0);
    try expect(mem.count() > keys_after_first);
}

test "a changed config_hash produces a miss" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var mem = MemStore.init(a);
    const fs = files(calc_src);

    var env1 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env1), mutantRunner(&env1), observation());
    const keys_after_first = mem.count();

    var obs2 = observation();
    obs2.config_hash = "sha256:1111111111111111";
    var env2 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env2), mutantRunner(&env2), obs2);
    try expect(env2.runs.load(.monotonic) > 0);
    try expect(mem.count() > keys_after_first);
}

test "without a store, keys are computed but reuse never fires (metadata-only)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fs = files(calc_src);
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const out = try rc.run(a, loadCfg(a, cfg_toml), &fs, .{}, baselineExecutor(&env), mutantRunner(&env), observation());

    // No store: every cacheable mutant ran, keys exist for metadata, mode stays
    // metadata_only, and there are zero hits (the prior behavior, preserved).
    try expect(env.runs.load(.monotonic) > 0);
    try expectEqual(report.CacheMode.metadata_only, out.cache.mode);
    try expect(out.cache.result_keys.len > 0);
    const diag = cache.toReportDiagnostics(out.cache);
    try expectEqual(@as(u64, 0), diag.hits);
    try expectEqual(@as(u64, @intCast(out.cache.result_keys.len)), diag.misses);
}

test "multi-mode runs do not reuse (key encodes only the primary mode)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const multi_cfg =
        \\[project]
        \\name = "sample"
        \\
        \\[zig]
        \\modes = ["Debug", "ReleaseFast"]
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub", "arithmetic_mul_div"]
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
    ;
    var mem = MemStore.init(a);
    const fs = files(calc_src);

    // Prime: a multi-mode run must not persist (reuse is single-mode only).
    var env1 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const first = try rc.run(a, loadCfg(a, multi_cfg), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env1), mutantRunner(&env1), observation());
    try expectEqual(@as(usize, 0), mem.puts); // nothing stored in multi-mode
    try expectEqual(report.CacheMode.metadata_only, first.cache.mode); // not read_write

    // A second multi-mode run still runs every mutant (no reuse).
    var env2 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    _ = try rc.run(a, loadCfg(a, multi_cfg), &fs, .{ .result_cache = mem.store() }, baselineExecutor(&env2), mutantRunner(&env2), observation());
    try expect(env2.runs.load(.monotonic) > 0);
}
