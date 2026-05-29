const std = @import("std");
const zentinel = @import("zentinel");
const runner = zentinel.runner;
const report = zentinel.report;
const command = zentinel.command;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const command_snapshot = @embedFile("fixtures/runner/baseline_command.json");

fn outcome(exit: ?i64, timed_out: bool, crashed: bool, stdout: []const u8, stderr: []const u8) runner.RawOutcome {
    return .{ .exit_code = exit, .timed_out = timed_out, .crashed = crashed, .duration_ms = 0, .stdout = stdout, .stderr = stderr };
}

/// Deterministic mock executor: returns programmed outcomes in order without
/// spawning any process (tests do not depend on machine-specific commands).
const Mock = struct {
    outcomes: []const runner.RawOutcome,
    next: usize = 0,

    fn run(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
        _ = argv;
        const self: *Mock = @ptrCast(@alignCast(ctx));
        const o = self.outcomes[self.next];
        self.next += 1;
        return o;
    }
    fn exec(self: *Mock) runner.Executor {
        return .{ .ctx = self, .runFn = Mock.run };
    }
};

test "passing baseline command classifies as passed with structured evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const outs = [_]runner.RawOutcome{outcome(0, false, false, "", "")};
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{"zig build test"}, "<project>");

    try expectEqual(report.BaselineStatus.passed, res.status);
    try expectEqual(@as(usize, 1), res.commands.len);
    const c = res.commands[0];
    try expectEqual(report.CommandStatus.passed, c.status);
    try expectEqual(report.FailureKind.none, c.failure_kind);
    try expectEqualStrings("zig build test", c.command.original);
    try expectEqual(@as(usize, 3), c.command.argv.len);
    try expectEqual(false, c.command.shell);
    try expect(c.command.environment_policy == .minimal);
    try expect(c.phase == .baseline);
    try expect(c.skip_reason == null);
}

test "failing baseline command classifies as failed with ZNTL_RUNNER_COMMAND_FAILED" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const outs = [_]runner.RawOutcome{outcome(1, false, false, "", "boom")};
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{"zig build test"}, "<project>");

    try expectEqual(report.BaselineStatus.failed, res.status);
    try expectEqual(report.CommandStatus.failed, res.commands[0].status);
    try expectEqual(report.FailureKind.test_failure, res.commands[0].failure_kind);
    try expectEqualStrings("ZNTL_RUNNER_COMMAND_FAILED", runner.statusCode(.failed));
}

test "baseline timeout maps to baseline failure with null exit code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const outs = [_]runner.RawOutcome{outcome(null, true, false, "", "")};
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{"zig build test"}, "<project>");

    try expectEqual(report.BaselineStatus.failed, res.status);
    try expectEqual(report.CommandStatus.timeout, res.commands[0].status);
    try expect(res.commands[0].timed_out);
    try expect(res.commands[0].exit_code == null);
    try expectEqualStrings("ZNTL_RUNNER_TIMEOUT", runner.statusCode(.timeout));
}

test "baseline compiler crash maps to compiler_crash, not internal error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const outs = [_]runner.RawOutcome{outcome(null, false, true, "", "panic")};
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{"zig build test"}, "<project>");

    try expectEqual(report.BaselineStatus.failed, res.status);
    try expectEqual(report.CommandStatus.compiler_crash, res.commands[0].status);
    try expectEqual(report.FailureKind.compiler_crash, res.commands[0].failure_kind);
    try expect(res.commands[0].exit_code == null);
}

test "captured output excerpts are bounded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const big = try a.alloc(u8, 5000);
    @memset(big, 'x');
    const outs = [_]runner.RawOutcome{outcome(0, false, false, big, big)};
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{"zig build test"}, "<project>");
    try expectEqual(@as(usize, runner.excerpt_limit), res.commands[0].evidence.stdout_excerpt.len);
    try expectEqual(@as(usize, runner.excerpt_limit), res.commands[0].evidence.stderr_excerpt.len);
}

test "commands execute in config order as parsed argv without a shell" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const outs = [_]runner.RawOutcome{ outcome(0, false, false, "", ""), outcome(0, false, false, "", "") };
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{ "zig build test", "zig test src/main.zig" }, "<project>");

    try expectEqual(@as(usize, 2), res.commands.len);
    try expectEqualStrings("zig build test", res.commands[0].command.original);
    try expectEqualStrings("zig test src/main.zig", res.commands[1].command.original);
    // Runner reuses the shared command parser argv shape (same as `zentinel check`).
    const parsed = try command.parse(a, "zig test src/main.zig");
    try expect(parsed == .ok);
    try expectEqual(parsed.ok.len, res.commands[1].command.argv.len);
    try expectEqualStrings(parsed.ok[2], res.commands[1].command.argv[2]);
    for (res.commands) |c| try expectEqual(false, c.command.shell);
}

test "baseline command evidence matches the documented snapshot shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const outs = [_]runner.RawOutcome{outcome(0, false, false, "", "")};
    var mock = Mock{ .outcomes = &outs };
    const res = try runner.runBaseline(a, mock.exec(), &.{"zig build test"}, "<project>");
    const json = try std.json.Stringify.valueAlloc(a, res.commands[0], .{ .whitespace = .indent_2 });
    try expectEqualStrings(command_snapshot, json);
}
