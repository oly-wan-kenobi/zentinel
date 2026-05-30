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
    const mutant_executor = rc.MutantRunner{ .ctx = &env, .runFn = mutantRunFn };

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

test "snapshot: selection metadata has exactly the documented fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const tests = try discover(a, "src/range.zig");
    const res = try ts.resolve(a, .same_file_then_package, "src/range.zig", tests, &configured, preflight(.passed), false);
    const json = try std.json.Stringify.valueAlloc(a, res.selection, .{ .whitespace = .indent_2 });

    const path = "test/fixtures/test_selection/selection_metadata.json";
    const existing = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20)) catch |err| switch (err) {
        error.FileNotFound => {
            try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = json });
            return;
        },
        else => return err,
    };
    try expectEqualStrings(existing, json);
}
