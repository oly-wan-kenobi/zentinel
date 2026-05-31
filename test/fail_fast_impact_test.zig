const std = @import("std");
const zentinel = @import("zentinel");

const runner = zentinel.runner;
const report = zentinel.report;
const ts = zentinel.test_selection;
const ast_backend = zentinel.ast_backend;
const rc = zentinel.run_command;
const config = zentinel.config;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// --- Baseline fail-fast -----------------------------------------------------

const Mock = struct {
    outcomes: []const runner.RawOutcome,
    calls: usize = 0,
    fn runFn(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
        _ = argv;
        const self: *Mock = @ptrCast(@alignCast(ctx));
        const i = self.calls;
        self.calls += 1;
        return self.outcomes[@min(i, self.outcomes.len - 1)];
    }
    fn exec(self: *Mock) runner.Executor {
        return .{ .ctx = self, .runFn = runFn };
    }
};

fn pass() runner.RawOutcome {
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}
fn fail() runner.RawOutcome {
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "boom" };
}

test "baseline fails fast: stops at the first failing command and runs no later command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const outs = [_]runner.RawOutcome{ fail(), pass() };
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{ "cmd-a", "cmd-b" }, "<project>");

    try expectEqual(report.BaselineStatus.failed, res.status);
    try expectEqual(@as(usize, 1), mock.calls); // the second command is never executed
    try expectEqual(@as(usize, 1), res.commands.len); // shortened: only the executed prefix is recorded
    try expectEqual(report.CommandStatus.failed, res.commands[0].status);
    // Baseline commands are never recorded as skipped (report invariant); the run
    // shortens by truncation so the report stays valid.
    for (res.commands) |c| try expect(c.status != .skipped);
}

test "baseline runs every command when all pass" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const outs = [_]runner.RawOutcome{ pass(), pass() };
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{ "cmd-a", "cmd-b" }, "<project>");
    try expectEqual(report.BaselineStatus.passed, res.status);
    try expectEqual(@as(usize, 2), mock.calls);
    try expectEqual(@as(usize, 2), res.commands.len);
}

// --- Deterministic impact selection ----------------------------------------

const sample = @embedFile("fixtures/impact_analysis/sample.zig");

test "impact_graph selects same-file tests in deterministic (line) order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(a, "src/sample.zig", sample);
    defer parsed.deinit();
    try expect(parsed.ok());
    const selected = try ts.sameFileTests(a, parsed, "src/sample.zig");
    try expect(selected.len == 2);
    // Declaration order is zeta-then-alpha; the deterministic order is by line.
    try expect(selected[0].line < selected[1].line);
    try expectEqualStrings("zeta covers add of positives", selected[0].name);
    try expectEqualStrings("alpha covers add of zero", selected[1].name);
}

test "impact_graph narrows to the same-file impact set when it is already covered" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parsed = try ast_backend.parse(a, "src/sample.zig", sample);
    defer parsed.deinit();
    const selected = try ts.sameFileTests(a, parsed, "src/sample.zig");

    // generated_in_baseline = true: the narrowed same-file command is part of the
    // baseline, so impact_graph runs only that command (no fallback).
    const resolution = try ts.resolve(a, .impact_graph, "src/sample.zig", selected, &.{"zig build test"}, null, true);
    try expectEqual(report.Strategy.impact_graph, resolution.selection.strategy);
    try expect(!resolution.selection.fallback_used);
    try expectEqual(@as(usize, 1), resolution.commands.len);
    try expectEqualStrings("zig test src/sample.zig", resolution.commands[0]);
}

test "impact_graph conservatively falls back to the full suite when impact is uncertain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parsed = try ast_backend.parse(a, "src/sample.zig", sample);
    defer parsed.deinit();
    const selected = try ts.sameFileTests(a, parsed, "src/sample.zig");

    // No passing preflight and not already in baseline -> conservative fallback.
    const resolution = try ts.resolve(a, .impact_graph, "src/sample.zig", selected, &.{"zig build test"}, null, false);
    try expectEqual(report.Strategy.impact_graph, resolution.selection.strategy);
    try expect(resolution.selection.fallback_used);
    try expectEqualStrings("zig build test", resolution.commands[0]);
}

// --- Skipped mutant commands carry documented reasons ----------------------

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
    return .{ .run_id = "run_failfast00000000000", .started_at = "1970-01-01T00:00:00Z", .project_root = "<project>", .zentinel_version = "0.0.0", .zig_version = "0.16.0", .config_hash = "sha256:0000000000000000", .duration_ms = 0 };
}

test "a fail-fast-shortened mutant records skipped commands with a documented reason" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const toml =
        \\[project]
        \\name = "sample"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
        \\[test]
        \\commands = ["zig build test", "zig test src/sample.zig"]
        \\selection = "all"
        \\
    ;
    var diag: config.Diagnostic = .{};
    const cfg = try config.load(a, toml, &diag);

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = fail() };
    const files = [_]rc.FileSource{.{ .path = "src/sample.zig", .source = sample }};
    const outcome = try rc.run(a, cfg, &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());

    try expect(outcome.report.mutants.len >= 1);
    const m = outcome.report.mutants[0];
    try expect(m.result.commands.len == 2);
    try expectEqual(report.CommandStatus.failed, m.result.commands[0].status);
    try expectEqual(report.CommandStatus.skipped, m.result.commands[1].status);
    try expect(m.result.commands[1].skip_reason != null);
    try expect(std.mem.indexOf(u8, m.result.commands[1].skip_reason.?, "fail-fast") != null);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "impact_graph selection produces a valid completed report end to end" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const toml =
        \\[project]
        \\name = "sample"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\selection = "impact_graph"
        \\
    ;
    var diag: config.Diagnostic = .{};
    const cfg = try config.load(a, toml, &diag);
    try expectEqualStrings("impact_graph", cfg.test_selection);

    var env = Env{ .arena = a, .baseline_outcome = pass(), .mutant_outcome = fail() };
    const files = [_]rc.FileSource{.{ .path = "src/sample.zig", .source = sample }};
    const outcome = try rc.run(a, cfg, &files, .{}, baselineExecutor(&env), mutantRunner(&env), observation());
    try expectEqual(report.RunStatus.completed, outcome.report.run.status);
    try expect(outcome.report.mutants.len >= 1);
    for (outcome.report.mutants) |m| try expectEqual(report.Strategy.impact_graph, m.test_selection.strategy);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}
