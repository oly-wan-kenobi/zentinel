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
};

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
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, env.cwd, ex, mode) catch @panic("mutant run failed");
}

fn baselineExecutor(env: *Env) runner.Executor {
    return .{ .ctx = env, .runFn = baselineCmd };
}
fn mutantRunner(env: *Env) rc.MutantRunner {
    return .{ .ctx = env, .runFn = mutantRunFn };
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

test "--output outside the project root is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    try expectError(error.OutputOutsideRoot, rc.run(a, loadCfg(a, cfg_toml), &files, .{ .output = "../escape.json" }, baselineExecutor(&env), mutantRunner(&env), observation()));
}

test "run.jobs > 1 is rejected until parallelism lands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const jobs_toml =
        \\[project]
        \\name = "sample"
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
        \\[run]
        \\jobs = 2
        \\
    ;

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = pass() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = calc_src }};

    try expectError(error.JobsNotSupported, rc.run(a, loadCfg(a, jobs_toml), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation()));
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

// --- Deterministic JSON snapshots ------------------------------------------

fn checkSnapshot(a: std.mem.Allocator, path: []const u8, actual: []const u8) !void {
    const io = std.testing.io;
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, a, std.Io.Limit.limited(1 << 20)) catch |err| switch (err) {
        error.FileNotFound => {
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = actual });
            return; // first run blesses the snapshot
        },
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
