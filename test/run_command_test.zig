const std = @import("std");
const zentinel = @import("zentinel");

const rc = zentinel.run_command;
const config = zentinel.config;
const runner = zentinel.runner;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;
const report = zentinel.report;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

// --- Fixtures --------------------------------------------------------------

const calc_src = "pub fn add(a: i32, b: i32) i32 {\n    return a + b;\n}\n";
const helper_src = "pub fn double(x: i32) i32 {\n    return x * 2;\n}\n";

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

test "backend parse error helper identifies the offending project-relative file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const files = [_]rc.FileSource{
        .{ .path = "src/ok.zig", .source = "pub fn ok() bool { return true; }\n" },
        .{ .path = "src/broken.zig", .source = "pub fn broken( {\n" },
    };
    const failed = (try rc.firstBackendParseError(a, &files)) orelse return error.TestUnexpectedResult;
    try expectEqualStrings("src/broken.zig", failed);
}

fn pass() runner.RawOutcome {
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}
fn failure() runner.RawOutcome {
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "test failed" };
}
fn timedOut() runner.RawOutcome {
    return .{ .exit_code = null, .timed_out = true, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}

// Test harness: a baseline outcome and a per-mutant command outcome. The mutant
// runner reuses the real `mutant_runner.run` (real patch validation + real
// classification) over a mock command executor, so these tests exercise the
// orchestration and report assembly, not stubbed statuses.
const Env = struct {
    arena: std.mem.Allocator,
    cwd: []const u8 = "<project>",
    baseline_outcome: runner.RawOutcome,
    mutant_outcome: runner.RawOutcome,
    /// Serializes the mock's allocations from the shared arena so the parallel
    /// worker-pool tests exercise real threads without racing the test arena.
    lock: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
};

fn spinLock(flag: *std.atomic.Value(u32)) void {
    while (flag.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}
fn spinUnlock(flag: *std.atomic.Value(u32)) void {
    flag.store(0, .release);
}

fn baselineCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    const env: *Env = @ptrCast(@alignCast(ctx));
    return env.baseline_outcome;
}
fn mutantCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    const env: *Env = @ptrCast(@alignCast(ctx));
    return env.mutant_outcome;
}
fn mutantRunFn(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *Env = @ptrCast(@alignCast(ctx));
    spinLock(&env.lock);
    defer spinUnlock(&env.lock);
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, env.cwd, ex, mode) catch @panic("mutant run failed");
}

fn baselineExecutor(env: *Env) runner.Executor {
    return .{ .ctx = env, .runFn = baselineCmd };
}
fn mutantRunner(env: *Env) rc.MutantRunner {
    return .{ .ctx = env, .runFn = mutantRunFn };
}

// --- Safety-mode matrix harness (task 058) ---------------------------------

const mode_matrix_cfg =
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

/// A per-call command outcome so the mock can return a mode-dependent result
/// while still going through the real `mutant_runner.run` classification.
const ModeCmdCtx = struct { outcome: runner.RawOutcome };
fn modeCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    return @as(*ModeCmdCtx, @ptrCast(@alignCast(ctx))).outcome;
}

/// Mode-aware mutant runner: the mutant's test fails (killed) under Debug/
/// ReleaseSafe safety checks but passes (survived) under ReleaseFast where the
/// check is elided -- a Debug-vs-ReleaseFast safety-mode effect.
fn modeAwareRunFn(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *Env = @ptrCast(@alignCast(ctx));
    spinLock(&env.lock);
    defer spinUnlock(&env.lock);
    var mc = ModeCmdCtx{ .outcome = if (mode == .ReleaseFast) pass() else failure() };
    const ex = runner.Executor{ .ctx = &mc, .runFn = modeCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, env.cwd, ex, mode) catch @panic("mutant run failed");
}

test "mode matrix records per-mode status, preserves result.mode, and flags mode effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};
    const mr = rc.MutantRunner{ .ctx = &env, .runFn = modeAwareRunFn };

    const outcome = try rc.run(a, loadCfg(a, mode_matrix_cfg), &files, .{}, baselineExecutor(&env), mr, observation());

    try expectEqual(report.RunStatus.completed, outcome.report.run.status);
    try expect(outcome.report.mutants.len > 0);
    const m0 = outcome.report.mutants[0];
    // result.mode stays the primary (first configured) mode, with the primary status.
    try expectEqual(report.Mode.Debug, m0.result.mode);
    try expectEqual(report.ResultStatus.killed, m0.result.status);
    // The additive matrix records both modes, sorted by canonical order.
    const mm = m0.result.mode_matrix orelse return error.TestUnexpectedResult;
    try expectEqual(@as(usize, 2), mm.len);
    try expectEqual(report.Mode.Debug, mm[0].mode);
    try expectEqual(report.ResultStatus.killed, mm[0].status);
    try expectEqual(report.Mode.ReleaseFast, mm[1].mode);
    try expectEqual(report.ResultStatus.survived, mm[1].status);
    try expect(zentinel.safety_modes.isModeDependent(mm));
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "single-mode runs do not populate result.mode_matrix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};
    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    try expect(outcome.report.mutants[0].result.mode_matrix == null);
}

test "the --mode override yields a single-mode report in the chosen mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};
    // Config has two modes, but --mode forces a single mode (no matrix).
    const outcome = try rc.run(a, loadCfg(a, mode_matrix_cfg), &files, .{ .mode_override = .ReleaseFast }, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqual(report.Mode.ReleaseFast, outcome.report.mutants[0].result.mode);
    try expect(outcome.report.mutants[0].result.mode_matrix == null);
}

// --- Orchestration / classification ---------------------------------------

test "baseline failure exits 3 with a baseline_failed report and no mutants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = failure(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());

    try expectEqual(@as(u8, 3), outcome.exit_code);
    try expectEqual(report.RunStatus.baseline_failed, outcome.report.run.status);
    try expectEqual(report.BaselineStatus.failed, outcome.report.baseline.status);
    try expectEqual(@as(usize, 0), outcome.report.mutants.len);
    try expectEqual(@as(u32, 0), outcome.report.summary.total);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "a failing test kills the mutant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());

    try expectEqual(@as(u8, 0), outcome.exit_code);
    try expectEqual(report.RunStatus.completed, outcome.report.run.status);
    try expectEqual(@as(usize, 1), outcome.report.mutants.len);
    try expectEqual(report.ResultStatus.killed, outcome.report.mutants[0].result.status);
    try expectEqual(@as(u32, 1), outcome.report.summary.killed);
    try expectEqual(@as(u32, 0), outcome.report.summary.survived);
    try expectEqualStrings("arithmetic_add_sub", outcome.report.mutants[0].operator);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "a passing test leaves the mutant surviving" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());

    try expectEqual(@as(u8, 0), outcome.exit_code);
    try expectEqual(report.ResultStatus.survived, outcome.report.mutants[0].result.status);
    try expectEqual(@as(u32, 1), outcome.report.summary.survived);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "--fail-on-survivors exits 1 when a mutant survives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .fail_on_survivors = true }, baselineExecutor(&env), mutantRunner(&env), observation());

    try expectEqual(@as(u8, 1), outcome.exit_code);
    try expectEqual(report.RunStatus.completed, outcome.report.run.status);
}

test "--operator filter narrows candidates to one operator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{
        .{ .path = "src/calc.zig", .source = calc_src },
        .{ .path = "src/helper.zig", .source = helper_src },
    };

    // Without a filter, both files contribute one candidate each.
    const all = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqual(@as(usize, 2), all.report.mutants.len);

    // With the filter, only the `*`->`/` candidate in helper.zig remains.
    const filtered = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .operator_filter = "arithmetic_mul_div" }, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqual(@as(usize, 1), filtered.report.mutants.len);
    try expectEqualStrings("arithmetic_mul_div", filtered.report.mutants[0].operator);
    try expectEqualStrings("src/helper.zig", filtered.report.mutants[0].file);
}

test "enabled operator filtering happens before physical-edit dedupe in run" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cfg =
        \\[project]
        \\name = "loop-only"
        \\
        \\[mutators]
        \\enabled = ["loop_boundary"]
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
    ;
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{
        .path = "src/loop.zig",
        .source =
        \\pub fn count(n: usize) usize {
        \\    var i: usize = 0;
        \\    while (i < n) : (i += 1) {}
        \\    return i;
        \\}
        ,
    }};

    const outcome = try rc.run(a, loadCfg(a, cfg), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqual(@as(usize, 1), outcome.report.mutants.len);
    try expectEqualStrings("loop_boundary", outcome.report.mutants[0].operator);
    try expectEqual(report.ResultStatus.killed, outcome.report.mutants[0].result.status);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "--mutant filter selects exactly one durable id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{
        .{ .path = "src/calc.zig", .source = calc_src },
        .{ .path = "src/helper.zig", .source = helper_src },
    };

    const all = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    const chosen = all.report.mutants[0].id;

    const filtered = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .mutant_filter = chosen }, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqual(@as(usize, 1), filtered.report.mutants.len);
    try expectEqualStrings(chosen, filtered.report.mutants[0].id);
}

test "run rejects invalid configured commands instead of misclassifying them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bad_command_cfg =
        \\[project]
        \\name = "bad-command"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
        \\[test]
        \\commands = ["zig test 'unterminated"]
        \\
    ;
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    try expectError(error.InvalidCommand, rc.run(a, loadCfg(a, bad_command_cfg), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation()));
}

test "--output outside the project root is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    try expectError(error.OutputOutsideRoot, rc.run(a, loadCfg(a, cfg_toml), &files, .{ .output = "../escape.json" }, baselineExecutor(&env), mutantRunner(&env), observation()));
}

test "run reports parse failures instead of silently dropping a source file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/broken.zig", .source = "pub fn broken(\n" }};

    try expectError(error.BackendParseError, rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation()));
}

// A source with several arithmetic operators so a run produces multiple mutants
// to actually schedule across workers.
const three_ops_src = "pub fn f(a: i32, b: i32) i32 {\n    return a + b - a * b + b;\n}\n";

const jobs_toml =
    \\[project]
    \\name = "sample"
    \\
    \\[mutators]
    \\enabled = ["arithmetic_add_sub", "arithmetic_mul_div"]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\
    \\[run]
    \\jobs = 4
    \\
;

fn crashed() runner.RawOutcome {
    return .{ .exit_code = null, .timed_out = false, .crashed = true, .duration_ms = 0, .stdout = "", .stderr = "" };
}

test "normalized run.jobs > 1 enables the worker pool instead of being rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/f.zig", .source = three_ops_src }};

    // After this task, run.jobs = 4 runs the worker pool rather than returning an error.
    const outcome = try rc.run(a, loadCfg(a, jobs_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqual(report.RunStatus.completed, outcome.report.run.status);
    try expect(outcome.report.mutants.len >= 3);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "worker count does not change report mutant order, ids, or statuses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]rc.FileSource{.{ .path = "src/f.zig", .source = three_ops_src }};

    var env1 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const serial = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .jobs = 1 }, baselineExecutor(&env1), mutantRunner(&env1), observation());

    var env8 = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const parallel = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .jobs = 8 }, baselineExecutor(&env8), mutantRunner(&env8), observation());

    try expect(serial.report.mutants.len >= 3); // several mutants actually scheduled
    try expectEqual(serial.report.mutants.len, parallel.report.mutants.len);
    for (serial.report.mutants, parallel.report.mutants) |s, p| {
        try expectEqualStrings(s.id, p.id);
        try expectEqual(s.display_id, p.display_id);
        try expectEqualStrings(s.operator, p.operator);
        try expectEqualStrings(s.file, p.file);
        try expectEqual(s.result.status, p.result.status);
    }
    try expectEqual(serial.report.summary.killed, parallel.report.summary.killed);
    try expectEqual(serial.report.summary.survived, parallel.report.summary.survived);
    try expectEqual(report.Violation.ok, report.validate(parallel.report));
}

test "--jobs parses, defaults to null, and rejects non-positive or non-numeric values" {
    try expectEqual(@as(?usize, 4), (try rc.parseArgs(&.{ "--jobs", "4" })).jobs);
    try expect((try rc.parseArgs(&.{})).jobs == null);
    try expectError(error.InvalidJobs, rc.parseArgs(&.{ "--jobs", "0" }));
    try expectError(error.InvalidJobs, rc.parseArgs(&.{ "--jobs", "-1" }));
    try expectError(error.InvalidJobs, rc.parseArgs(&.{ "--jobs", "abc" }));
    try expectError(error.MissingValue, rc.parseArgs(&.{"--jobs"}));
}

test "--jobs overrides run.jobs and stays bounded for huge values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]rc.FileSource{.{ .path = "src/f.zig", .source = three_ops_src }};

    // jobs_toml requests run.jobs = 4, but an explicit --jobs of 1 forces serial
    // execution, and a huge --jobs is clamped rather than spawning unbounded
    // threads; both still produce a valid report.
    var env_serial = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const serial = try rc.run(a, loadCfg(a, jobs_toml), &files, .{ .jobs = 1 }, baselineExecutor(&env_serial), mutantRunner(&env_serial), observation());
    try expectEqual(report.Violation.ok, report.validate(serial.report));

    var env_huge = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const huge = try rc.run(a, loadCfg(a, jobs_toml), &files, .{ .jobs = 100000 }, baselineExecutor(&env_huge), mutantRunner(&env_huge), observation());
    try expectEqual(serial.report.mutants.len, huge.report.mutants.len);
    try expectEqual(report.Violation.ok, report.validate(huge.report));
}

test "a crashing mutant command propagates its terminal status under parallel execution" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]rc.FileSource{.{ .path = "src/f.zig", .source = three_ops_src }};

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = crashed() };
    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .jobs = 8 }, baselineExecutor(&env), mutantRunner(&env), observation());
    try expect(outcome.report.mutants.len >= 3);
    for (outcome.report.mutants) |m| {
        try expectEqual(report.ResultStatus.compiler_crash, m.result.status);
    }
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

// --- Option parsing --------------------------------------------------------

test "parseArgs reads every documented run option" {
    const args = [_][]const u8{ "--operator", "arithmetic_add_sub", "--mutant", "m_abc", "--fail-on-survivors", "--report", "json", "--output", "out/report.json" };
    const opts = try rc.parseArgs(&args);
    try expectEqualStrings("arithmetic_add_sub", opts.operator_filter.?);
    try expectEqualStrings("m_abc", opts.mutant_filter.?);
    try expect(opts.fail_on_survivors);
    try expectEqual(rc.ReportFormat.json, opts.report_format);
    try expectEqualStrings("out/report.json", opts.output.?);
}

test "parseArgs defaults are conservative" {
    const opts = try rc.parseArgs(&.{});
    try expect(opts.operator_filter == null);
    try expect(opts.mutant_filter == null);
    try expect(!opts.fail_on_survivors);
    try expectEqual(rc.ReportFormat.text, opts.report_format);
    try expect(opts.output == null);
}

test "parseArgs rejects unknown options and missing values instead of ignoring them" {
    try expectError(error.UnknownOption, rc.parseArgs(&.{"--nope"}));
    try expectError(error.MissingValue, rc.parseArgs(&.{"--operator"}));
    try expectError(error.MissingValue, rc.parseArgs(&.{"--output"}));
    try expectError(error.InvalidReportFormat, rc.parseArgs(&.{ "--report", "yaml" }));
}

test "parseArgs accepts jsonl and junit report formats" {
    try expectEqual(rc.ReportFormat.jsonl, (try rc.parseArgs(&.{ "--report", "jsonl" })).report_format);
    try expectEqual(rc.ReportFormat.junit, (try rc.parseArgs(&.{ "--report", "junit" })).report_format);
}

test "report format selection does not change canonical report data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const as_text = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .report_format = .text }, baselineExecutor(&env), mutantRunner(&env), observation());
    const as_junit = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .report_format = .junit }, baselineExecutor(&env), mutantRunner(&env), observation());

    // The report data (and its canonical JSON) is identical regardless of the
    // chosen render format; --report only selects the renderer in the adapter.
    try expectEqualStrings(try report.toJson(a, as_text.report), try report.toJson(a, as_junit.report));
}

test "--verbose and --quiet parse as run options without affecting report data" {
    const verbose = try rc.parseArgs(&.{"--verbose"});
    try expect(verbose.verbose);
    try expect(!verbose.quiet);

    const quiet = try rc.parseArgs(&.{"--quiet"});
    try expect(quiet.quiet);
    try expect(!quiet.verbose);

    // Verbosity is not an input to the deterministic run: identical reports.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};
    const loud = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .verbose = true }, baselineExecutor(&env), mutantRunner(&env), observation());
    const hushed = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .quiet = true }, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqualStrings(try report.toJson(a, loud.report), try report.toJson(a, hushed.report));
}

test "--no-cache parses as a run option" {
    try expect((try rc.parseArgs(&.{"--no-cache"})).no_cache);
    try expect(!(try rc.parseArgs(&.{})).no_cache);
}

test "--no-cache disables the result cache but keeps build-cache isolation and report data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const cached = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    const uncached = try rc.run(a, loadCfg(a, cfg_toml), &files, .{ .no_cache = true }, baselineExecutor(&env), mutantRunner(&env), observation());

    // Default: metadata-only key computation, result keys present, no reuse.
    try expectEqual(report.CacheMode.metadata_only, cached.cache.mode);
    try expect(cached.cache.enabled);
    try expectEqual(@as(usize, 1), cached.cache.result_keys.len);

    // --no-cache: result cache disabled with no result keys, but the Zig
    // build-cache isolation metadata is still present.
    try expectEqual(report.CacheMode.disabled, uncached.cache.mode);
    try expect(!uncached.cache.enabled);
    try expectEqual(@as(usize, 0), uncached.cache.result_keys.len);
    try expect(uncached.cache.build_cache.isolated);

    // Cache policy never changes mutant correctness: identical canonical reports.
    try expectEqualStrings(try report.toJson(a, cached.report), try report.toJson(a, uncached.report));
}

// --- Deterministic JSON snapshots ------------------------------------------

fn checkSnapshot(a: std.mem.Allocator, path: []const u8, actual: []const u8) !void {
    const io = std.testing.io;
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, a, std.Io.Limit.limited(1 << 20)) catch |err| switch (err) {
        error.FileNotFound => return err,
        else => return err,
    };
    try expectEqualStrings(existing, actual);
}

test "snapshot: completed run with one killed mutant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = failure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    const json = try report.toJson(a, outcome.report);
    try checkSnapshot(a, "test/snapshots/run_command_completed.json", json);
}

test "snapshot: baseline failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = failure(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    const json = try report.toJson(a, outcome.report);
    try checkSnapshot(a, "test/snapshots/run_command_baseline_failed.json", json);
}

test "snapshot: baseline timeout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = timedOut(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    const outcome = try rc.run(a, loadCfg(a, cfg_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqual(report.RunStatus.baseline_failed, outcome.report.run.status);
    const json = try report.toJson(a, outcome.report);
    try checkSnapshot(a, "test/snapshots/run_command_baseline_timeout.json", json);
}

// --- `run --backend` is list-mutants-only (task 114) -----------------------

fn readDoc(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

test "run rejects --backend with a dedicated error and the backend docs state the honest re-tag, list-mutants-only scope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The experimental ZIR/AIR backends are reachable only from `list-mutants`
    // (they re-tag AST candidates, they do no IR analysis). `run --backend <...>`
    // is rejected with a dedicated error -- not the generic UnknownOption, and
    // never silently ignored.
    try expectError(error.BackendNotInRun, rc.parseArgs(&.{ "--backend", "zir" }));
    try expectError(error.BackendNotInRun, rc.parseArgs(&.{ "--backend", "air" }));
    // A real run option still parses (the dedicated rejection is specific to --backend).
    _ = try rc.parseArgs(&.{"--fail-on-survivors"});

    // The backend docs describe the prototypes honestly: they re-tag AST
    // candidates and `--backend` is list-mutants-only (no IR-level analysis).
    for ([_][]const u8{ "docs/ZIR_BACKEND.md", "docs/AIR_BACKEND.md" }) |doc| {
        const text = try readDoc(a, doc);
        try expect(std.mem.indexOf(u8, text, "re-tag") != null);
        try expect(std.mem.indexOf(u8, text, "list-mutants") != null);
    }
}
