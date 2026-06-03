// SEM-1c proof (ZIR_IMPROVEMENTS.md "Beyond ZIR"): the reported `expected_compile`
// is the compiler's ACTUAL verdict for a run mutant, not the per-operator heuristic
// guess. Two halves:
//   * pure unit tests of `semantic_filter.empiricalExpectedCompile` (the mapping);
//   * end-to-end wiring tests that drive a mutant through the real run path and
//     assert the report entry carries the empirical bucket. These are the red->green
//     proof: before `buildEntry` was wired they showed the heuristic guess.
const std = @import("std");
const zentinel = @import("zentinel");

const rc = zentinel.run_command;
const config = zentinel.config;
const runner = zentinel.runner;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;
const report = zentinel.report;
const semantic_filter = zentinel.semantic_filter;

const expectEqual = std.testing.expectEqual;

// --- pure mapping: the compiler's verdict overrides the heuristic guess ---------

test "empiricalExpectedCompile: a rejected mutant is must_fail even when the heuristic guessed compiles" {
    try expectEqual(mutant.ExpectedCompile.must_fail, semantic_filter.empiricalExpectedCompile(.compiles, .compile_error));
}

test "empiricalExpectedCompile: a may_fail guess that actually compiled is resolved to compiles" {
    // survived and killed both mean the test binary ran -> the mutant compiled.
    try expectEqual(mutant.ExpectedCompile.compiles, semantic_filter.empiricalExpectedCompile(.may_fail, .survived));
    try expectEqual(mutant.ExpectedCompile.compiles, semantic_filter.empiricalExpectedCompile(.may_fail, .killed));
}

test "empiricalExpectedCompile: a compiles guess that compiled stays compiles (agreement unchanged)" {
    try expectEqual(mutant.ExpectedCompile.compiles, semantic_filter.empiricalExpectedCompile(.compiles, .killed));
}

test "empiricalExpectedCompile: ambiguous outcomes carry no verdict, so the heuristic is kept" {
    try expectEqual(mutant.ExpectedCompile.may_fail, semantic_filter.empiricalExpectedCompile(.may_fail, .timeout));
    try expectEqual(mutant.ExpectedCompile.compiles, semantic_filter.empiricalExpectedCompile(.compiles, .compiler_crash));
    try expectEqual(mutant.ExpectedCompile.must_fail, semantic_filter.empiricalExpectedCompile(.must_fail, .invalid));
    try expectEqual(mutant.ExpectedCompile.may_fail, semantic_filter.empiricalExpectedCompile(.may_fail, .skipped));
}

// --- end-to-end wiring through the real run path --------------------------------

fn pass() runner.RawOutcome {
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}
fn testFailure() runner.RawOutcome {
    // exit!=0 with no compile diagnostic and no runner summary -> test_failure -> killed.
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "test failed" };
}
fn compileError() runner.RawOutcome {
    // a Zig `: error: ` diagnostic with no runner summary -> compile_error.
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "src/cmp.zig:2:14: error: incompatible types" };
}
fn timedOut() runner.RawOutcome {
    return .{ .exit_code = null, .timed_out = true, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}

const Env = struct {
    arena: std.mem.Allocator,
    cwd: []const u8 = "<project>",
    baseline_outcome: runner.RawOutcome,
    mutant_outcome: runner.RawOutcome,
};

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
    return mutant_runner.run(env.arena, m, source, .created, commands, env.cwd, ex, mode) catch @panic("mutant run failed");
}
fn baselineExecutor(env: *Env) runner.Executor {
    return .{ .ctx = env, .runFn = baselineCmd };
}
fn mutantRunner(env: *Env) rc.MutantRunner {
    return .{ .ctx = env, .runFn = mutantRunFn };
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
fn loadCfg(a: std.mem.Allocator, toml: []const u8) config.Config {
    var diag: config.Diagnostic = .{};
    return config.load(a, toml, &diag) catch @panic("config did not parse");
}

fn entryFor(rep: report.Report, operator: []const u8) report.Mutant {
    for (rep.mutants) |m| {
        if (std.mem.eql(u8, m.operator, operator)) return m;
    }
    @panic("expected a mutant for the operator");
}

const cmp_cfg =
    \\[project]
    \\name = "sample"
    \\
    \\[mutators]
    \\enabled = ["comparison_boundary"]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\
;
const arith_cfg =
    \\[project]
    \\name = "sample"
    \\
    \\[mutators]
    \\enabled = ["arithmetic_add_sub"]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\
;
const cmp_src = "pub fn lt(a: i32, b: i32) bool {\n    return a < b;\n}\n";
const arith_src = "pub fn add(a: i32, b: i32) i32 {\n    return a + b;\n}\n";

test "run path: a comparison mutant the compiler rejects is reported must_fail (heuristic guessed compiles)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = compileError() };
    const files = [_]rc.FileSource{.{ .path = "src/cmp.zig", .source = cmp_src }};
    const outcome = try rc.run(a, loadCfg(a, cmp_cfg), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());

    const e = entryFor(outcome.report, "comparison_boundary");
    // comparison_boundary's per-operator heuristic is `.compiles`; the compiler's
    // actual verdict (compile_error) overrides it.
    try expectEqual(report.ResultStatus.compile_error, e.result.status);
    try expectEqual(mutant.ExpectedCompile.must_fail, e.expected_compile);
}

test "run path: an arithmetic mutant that actually compiled is reported compiles (heuristic guessed may_fail)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = testFailure() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = arith_src }};
    const outcome = try rc.run(a, loadCfg(a, arith_cfg), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());

    const e = entryFor(outcome.report, "arithmetic_add_sub");
    // arithmetic's per-operator heuristic is `.may_fail`; the mutant ran (killed),
    // so it compiled -> the guess is resolved to `.compiles`.
    try expectEqual(report.ResultStatus.killed, e.result.status);
    try expectEqual(mutant.ExpectedCompile.compiles, e.expected_compile);
}

test "run path: an ambiguous (timeout) outcome keeps the arithmetic may_fail heuristic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = timedOut() };
    const files = [_]rc.FileSource{.{ .path = "src/calc.zig", .source = arith_src }};
    const outcome = try rc.run(a, loadCfg(a, arith_cfg), &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());

    const e = entryFor(outcome.report, "arithmetic_add_sub");
    try expectEqual(report.ResultStatus.timeout, e.result.status);
    try expectEqual(mutant.ExpectedCompile.may_fail, e.expected_compile);
}
