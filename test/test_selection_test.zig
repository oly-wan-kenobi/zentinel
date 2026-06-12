const std = @import("std");
const zentinel = @import("zentinel");

const ts = zentinel.test_selection;
const ast = zentinel.ast_backend;
const report = zentinel.report;
const rc = zentinel.run_command;
const runner = zentinel.runner;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;
const config = zentinel.config;
const command = zentinel.command;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

const configured = [_][]const u8{"zig build test"};

fn preflight(status: report.CommandStatus) report.CommandResult {
    return .{
        .command = .{ .original = "zig test src/range.zig", .argv = &.{ "zig", "test", "src/range.zig" }, .cwd = "<project>", .environment_policy = .minimal, .shell = false },
        .phase = .selection_preflight,
        .status = status,
        .exit_code = if (status == .passed) 0 else 1,
        .timed_out = false,
        .failure_kind = if (status == .passed) .none else .test_failure,
        .duration_ms = 0,
        .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "", .failure_summary = "" },
        .skip_reason = null,
    };
}

fn discover(a: std.mem.Allocator, label: []const u8) ![]report.SelectedTest {
    const source = try readFixture(a, "test/fixtures/test_selection/with_tests.zig");
    var parsed = try ast.parse(a, label, source);
    defer parsed.deinit();
    return ts.sameFileTests(a, parsed, label);
}

test "same-file tests are discovered and ordered by file, line, name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tests = try discover(a, "src/range.zig");
    try expectEqual(@as(usize, 2), tests.len);
    try expectEqualStrings("add is correct", tests[0].name);
    try expectEqual(@as(u32, 7), tests[0].line);
    try expectEqualStrings("add handles zero", tests[1].name);
    try expectEqual(@as(u32, 11), tests[1].line);
    // Ordered by line ascending.
    try expect(tests[0].line < tests[1].line);
}

test "files without same-file tests yield no selected tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try readFixture(a, "test/fixtures/test_selection/no_tests.zig");
    var parsed = try ast.parse(a, "src/util.zig", source);
    defer parsed.deinit();
    const tests = try ts.sameFileTests(a, parsed, "src/util.zig");
    try expectEqual(@as(usize, 0), tests.len);
}

test "same_file_then_package selects zig test <file> when the preflight passes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tests = try discover(a, "src/range.zig");
    const res = try ts.resolve(a, .same_file_then_package, "src/range.zig", tests, &configured, preflight(.passed), false);

    try expectEqual(@as(usize, 1), res.commands.len);
    try expectEqualStrings("zig test src/range.zig", res.commands[0]);
    try expect(!res.selection.fallback_used);
    try expectEqual(@as(usize, 1), res.selection.preflight_commands.len);
    try expectEqual(report.Phase.selection_preflight, res.selection.preflight_commands[0].phase);
    try expectEqual(report.Strategy.same_file_then_package, res.selection.strategy);
    try expectEqual(@as(usize, 2), res.selection.selected.len);
}

test "generated same-file command preserves path bytes through shell-free argv parsing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const generated = try ts.generatedCommand(a, "src/with space/[range].zig");
    try expectEqualStrings("zig test \"src/with space/[range].zig\"", generated);

    const argv = try ts.generatedCommandArgv(a, "src/with space/[range].zig");
    try expectEqual(@as(usize, 3), argv.len);
    try expectEqualStrings("zig", argv[0]);
    try expectEqualStrings("test", argv[1]);
    try expectEqualStrings("src/with space/[range].zig", argv[2]);
}

test "a failed preflight falls back to configured commands and records the evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tests = try discover(a, "src/range.zig");
    const res = try ts.resolve(a, .same_file_then_package, "src/range.zig", tests, &configured, preflight(.failed), false);

    try expectEqual(@as(usize, 1), res.commands.len);
    try expectEqualStrings("zig build test", res.commands[0]);
    try expect(res.selection.fallback_used);
    // The failed preflight is still recorded as evidence.
    try expectEqual(@as(usize, 1), res.selection.preflight_commands.len);
    try expectEqual(report.CommandStatus.failed, res.selection.preflight_commands[0].status);
}

test "missing same-file tests fall back to configured commands" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const res = try ts.resolve(a, .same_file_then_package, "src/util.zig", &.{}, &configured, null, false);
    try expectEqualStrings("zig build test", res.commands[0]);
    try expect(res.selection.fallback_used);
    try expectEqual(@as(usize, 0), res.selection.selected.len);
    try expectEqual(@as(usize, 0), res.selection.preflight_commands.len);
}

test "a generated command already in the baseline set needs no preflight" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tests = try discover(a, "src/range.zig");
    const baseline = [_][]const u8{"zig test src/range.zig"};
    const res = try ts.resolve(a, .same_file_then_package, "src/range.zig", tests, &baseline, null, true);

    try expectEqualStrings("zig test src/range.zig", res.commands[0]);
    try expect(!res.selection.fallback_used);
    try expectEqual(@as(usize, 0), res.selection.preflight_commands.len);
}

test "the all strategy runs configured commands with no selection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const res = try ts.resolve(a, .all, "src/range.zig", &.{}, &configured, null, false);
    try expectEqualStrings("zig build test", res.commands[0]);
    try expect(!res.selection.fallback_used);
    try expectEqual(@as(usize, 0), res.selection.selected.len);
}

// --- run command integration (preflight path) ------------------------------

const RunEnv = struct {
    arena: std.mem.Allocator,
    baseline_outcome: runner.RawOutcome,
    mutant_outcome: runner.RawOutcome,
};

fn okOutcome() runner.RawOutcome {
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}
fn failOutcome() runner.RawOutcome {
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "x" };
}

fn baselineCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    const env: *RunEnv = @ptrCast(@alignCast(ctx));
    return env.baseline_outcome;
}
fn mutantCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    const env: *RunEnv = @ptrCast(@alignCast(ctx));
    return env.mutant_outcome;
}
fn mutantRunFn(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *RunEnv = @ptrCast(@alignCast(ctx));
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, "<project>", ex, mode) catch @panic("mutant run failed");
}
fn mutantRunSpecsFn(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const command.Spec, mode: report.Mode) mutant_runner.MutationResult {
    const env: *RunEnv = @ptrCast(@alignCast(ctx));
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.runSpecs(env.arena, m, source, .created, commands, "<project>", ex, mode) catch @panic("mutant run failed");
}

fn runObservation() rc.Observation {
    return .{ .run_id = "run_sel", .started_at = "1970-01-01T00:00:00Z", .project_root = "<project>", .zentinel_version = "0.0.0", .zig_version = "0.16.0", .config_hash = "sha256:0", .duration_ms = 0 };
}

test "run integrates same-file selection with a passing preflight" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try readFixture(a, "test/fixtures/test_selection/with_tests.zig");
    const files = [_]rc.FileSource{.{ .path = "src/range.zig", .source = source }};

    var diag: config.Diagnostic = .{};
    const cfg = try config.load(a,
        \\[project]
        \\name = "sel"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
    , &diag);

    // Baseline and preflight pass; the mutant fails the selected command -> killed.
    var env = RunEnv{ .arena = a, .baseline_outcome = okOutcome(), .mutant_outcome = failOutcome() };
    const baseline_executor = runner.Executor{ .ctx = &env, .runFn = baselineCmd };
    const mutant_executor = rc.MutantRunner{ .ctx = &env, .runFn = mutantRunFn, .runSpecsFn = mutantRunSpecsFn };

    const outcome = try rc.run(a, cfg, &files, .{}, baseline_executor, mutant_executor, runObservation());

    try expectEqual(@as(usize, 1), outcome.report.mutants.len);
    const sel = outcome.report.mutants[0].test_selection;
    try expectEqual(report.Strategy.same_file_then_package, sel.strategy);
    try expectEqual(@as(usize, 2), sel.selected.len); // 2 same-file tests discovered
    try expectEqual(@as(usize, 1), sel.commands.len);
    try expectEqualStrings("zig test src/range.zig", sel.commands[0]);
    try expectEqual(@as(usize, 1), sel.preflight_commands.len);
    try expectEqual(report.Phase.selection_preflight, sel.preflight_commands[0].phase);
    try expectEqual(report.CommandStatus.passed, sel.preflight_commands[0].status);
    try expect(!sel.fallback_used);
    // The mutant ran the selected command and was killed; it still appears in the report (I-012).
    try expectEqual(report.ResultStatus.killed, outcome.report.mutants[0].result.status);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "run executes generated same-file commands with exact argv for metacharacter paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try readFixture(a, "test/fixtures/test_selection/with_tests.zig");
    const files = [_]rc.FileSource{.{ .path = "src/with$dollar.zig", .source = source }};

    var diag: config.Diagnostic = .{};
    const cfg = try config.load(a,
        \\[project]
        \\name = "sel"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
    , &diag);

    var env = RunEnv{ .arena = a, .baseline_outcome = okOutcome(), .mutant_outcome = failOutcome() };
    const baseline_executor = runner.Executor{ .ctx = &env, .runFn = baselineCmd };
    const mutant_executor = rc.MutantRunner{ .ctx = &env, .runFn = mutantRunFn, .runSpecsFn = mutantRunSpecsFn };

    const outcome = try rc.run(a, cfg, &files, .{}, baseline_executor, mutant_executor, runObservation());
    try expectEqual(@as(usize, 1), outcome.report.mutants.len);
    const m = outcome.report.mutants[0];
    try expect(!m.test_selection.fallback_used);
    try expectEqual(@as(usize, 1), m.test_selection.preflight_commands.len);
    try expectEqual(report.CommandStatus.passed, m.test_selection.preflight_commands[0].status);
    try expectEqual(@as(usize, 3), m.test_selection.preflight_commands[0].command.argv.len);
    try expectEqualStrings("src/with$dollar.zig", m.test_selection.preflight_commands[0].command.argv[2]);
    try expectEqual(report.ResultStatus.killed, m.result.status);
    try expectEqual(@as(usize, 1), m.result.commands.len);
    try expectEqualStrings("src/with$dollar.zig", m.result.commands[0].command.argv[2]);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "snapshot: selection metadata has exactly the documented fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tests = try discover(a, "src/range.zig");
    const res = try ts.resolve(a, .same_file_then_package, "src/range.zig", tests, &configured, preflight(.passed), false);
    const json = try std.json.Stringify.valueAlloc(a, res.selection, .{ .whitespace = .indent_2 });

    const path = "test/fixtures/test_selection/selection_metadata.json";
    const existing = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20)) catch |err| switch (err) {
        error.FileNotFound => return err,
        else => return err,
    };
    try expectEqualStrings(existing, json);
}

// --- Soundness: narrowed-selection survivors re-verified ----------
//
// The default `same_file_then_package` strategy may run `zig test <file>` instead
// of the configured `zig build test`. That generated command is weaker: a mutant
// whose function is covered only by a sibling `*_test.zig` survives `zig test
// <file>` but is killed by the configured suite. A `survived` verdict from the
// narrowed selection is therefore unsound until the configured suite is confirmed
// to also miss the mutant.

const SoundEnv = struct { arena: std.mem.Allocator };

/// Baseline + same-file preflight run against the UNMUTATED project and pass.
fn soundBaseline(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = ctx;
    _ = argv;
    return okOutcome();
}

/// The configured suite (`zig build test`, exercising a sibling `*_test.zig`)
/// KILLS the mutant; the narrowed same-file command (`zig test src/range.zig`)
/// does NOT. Branch on the parsed argv so the executor models a real project
/// where the same-file tests are insufficient.
fn killedByConfiguredCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = ctx;
    for (argv) |part| {
        if (std.mem.eql(u8, part, "build")) return failOutcome();
    }
    return okOutcome();
}

/// Every command passes: a genuine survivor that must still be re-verified
/// against, and recorded with, the configured suite.
fn survivesEverythingCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = ctx;
    _ = argv;
    return okOutcome();
}

fn killedByConfiguredRun(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *SoundEnv = @ptrCast(@alignCast(ctx));
    const ex = runner.Executor{ .ctx = env, .runFn = killedByConfiguredCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, "<project>", ex, mode) catch @panic("mutant run failed");
}

fn survivesEverythingRun(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *SoundEnv = @ptrCast(@alignCast(ctx));
    const ex = runner.Executor{ .ctx = env, .runFn = survivesEverythingCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, "<project>", ex, mode) catch @panic("mutant run failed");
}

fn soundCfg(a: std.mem.Allocator) !config.Config {
    var diag: config.Diagnostic = .{};
    return config.load(a,
        \\[project]
        \\name = "sel"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
    , &diag);
}

test "needsConfiguredReverification: a narrowed selection needs re-verification, the configured set does not" {
    const configured_set = [_][]const u8{"zig build test"};
    const narrowed = [_][]const u8{"zig test src/range.zig"};
    // A generated same-file command differs from the configured suite -> escalate.
    try expect(ts.needsConfiguredReverification(&narrowed, &configured_set));
    // The configured set against itself (the `all` strategy / a fallback) -> no escalation.
    try expect(!ts.needsConfiguredReverification(&configured_set, &configured_set));
    // A strict subset of a multi-command configured suite is still narrowed, even
    // when the generated command happens to be one of the baseline commands.
    const multi = [_][]const u8{ "zig build test", "zig test src/range.zig" };
    const subset = [_][]const u8{"zig test src/range.zig"};
    try expect(ts.needsConfiguredReverification(&subset, &multi));
}

test "a same-file survivor the configured suite kills is reported killed, not survived" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try readFixture(a, "test/fixtures/test_selection/with_tests.zig");
    const files = [_]rc.FileSource{.{ .path = "src/range.zig", .source = source }};
    const cfg = try soundCfg(a);

    var env = SoundEnv{ .arena = a };
    const baseline_executor = runner.Executor{ .ctx = &env, .runFn = soundBaseline };
    const mutant_executor = rc.MutantRunner{ .ctx = &env, .runFn = killedByConfiguredRun };

    const outcome = try rc.run(a, cfg, &files, .{}, baseline_executor, mutant_executor, runObservation());

    try expectEqual(@as(usize, 1), outcome.report.mutants.len);
    const m = outcome.report.mutants[0];

    // The selection still narrowed to the same-file command...
    try expectEqual(report.Strategy.same_file_then_package, m.test_selection.strategy);
    try expectEqual(@as(usize, 1), m.test_selection.commands.len);
    try expectEqualStrings("zig test src/range.zig", m.test_selection.commands[0]);

    // ...but the configured suite kills the mutant, so the sound verdict is
    // `killed`, never `survived` (the re-verification soundness guarantee). Without
    // re-verification the narrowed `zig test src/range.zig` passes and the mutant
    // is falsely reported `survived`.
    try expectEqual(report.ResultStatus.killed, m.result.status);
    try expectEqual(@as(u64, 0), outcome.report.summary.survived);
    try expectEqual(@as(u64, 1), outcome.report.summary.killed);

    // The configured re-verification command is recorded in the evidence and is
    // the killing command (I-012: nothing is hidden from the report).
    var saw_configured_kill = false;
    for (m.result.commands) |c| {
        if (std.mem.eql(u8, c.command.original, "zig build test") and c.status == .failed) saw_configured_kill = true;
    }
    try expect(saw_configured_kill);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}

test "a genuine same-file survivor is confirmed against and recorded with the configured suite" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try readFixture(a, "test/fixtures/test_selection/with_tests.zig");
    const files = [_]rc.FileSource{.{ .path = "src/range.zig", .source = source }};
    const cfg = try soundCfg(a);

    var env = SoundEnv{ .arena = a };
    const baseline_executor = runner.Executor{ .ctx = &env, .runFn = soundBaseline };
    const mutant_executor = rc.MutantRunner{ .ctx = &env, .runFn = survivesEverythingRun };

    const outcome = try rc.run(a, cfg, &files, .{}, baseline_executor, mutant_executor, runObservation());

    try expectEqual(@as(usize, 1), outcome.report.mutants.len);
    const m = outcome.report.mutants[0];

    // The mutant survives the configured suite too, so it stays `survived` -- the
    // re-verification must not over-kill a genuine survivor.
    try expectEqual(report.ResultStatus.survived, m.result.status);
    try expectEqual(@as(u64, 1), outcome.report.summary.survived);

    // The recorded survivor was confirmed against the configured suite: both the
    // narrowed command and the configured command appear (passing) in the
    // evidence, so a `survived` verdict is never based only on the narrowed subset.
    var saw_narrowed = false;
    var saw_configured = false;
    for (m.result.commands) |c| {
        if (std.mem.eql(u8, c.command.original, "zig test src/range.zig")) saw_narrowed = true;
        if (std.mem.eql(u8, c.command.original, "zig build test")) saw_configured = true;
    }
    try expect(saw_narrowed);
    try expect(saw_configured);
    try expectEqual(report.Violation.ok, report.validate(outcome.report));
}
