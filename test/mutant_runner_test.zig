const std = @import("std");
const zentinel = @import("zentinel");
const mutant_runner = zentinel.mutant_runner;
const runner = zentinel.runner;
const mutant = zentinel.mutant;
const report = zentinel.report;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const target_path = "test/fixtures/mutant_runner/target.zig";

fn readTarget(a: std.mem.Allocator) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, target_path, a, std.Io.Limit.limited(1 << 20));
}

fn plusMutant(source: []const u8, original: []const u8) mutant.Mutant {
    const at: u32 = @intCast(std.mem.indexOf(u8, source, "a + b").? + 2);
    return .{
        .id = "m_demo",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = "arithmetic_add_sub",
        .operator_stability = .stable,
        .file = "target.zig",
        .span = .{ .byte_start = at, .byte_end = at + 1, .line_start = 2, .column_start = 14, .line_end = 2, .column_end = 15 },
        .original = original,
        .replacement = "-",
        .expected_compile = .may_fail,
    };
}

fn outcome(exit: ?i64, timed_out: bool, crashed: bool) runner.RawOutcome {
    return .{ .exit_code = exit, .timed_out = timed_out, .crashed = crashed, .duration_ms = 0, .stdout = "", .stderr = "" };
}

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

fn classify(a: std.mem.Allocator, source: []const u8, original: []const u8, workspace: mutant_runner.WorkspaceOutcome, commands: []const []const u8, outs: []const runner.RawOutcome) !mutant_runner.MutationResult {
    var mock = Mock{ .outcomes = outs };
    return mutant_runner.run(a, plusMutant(source, original), source, workspace, commands, "<project>", mock.exec(), .Debug);
}

test "mutant whose tests fail is classified killed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readTarget(a);
    const res = try classify(a, src, "+", .created, &.{"zig build test"}, &.{outcome(1, false, false)});
    try expectEqual(report.ResultStatus.killed, res.status);
    try expect(res.classifier_source == .runner_command_evidence);
    try expect(res.commands[0].phase == .mutant);
    try expect(res.commands[0].command.argv.len == 3); // structured argv, not a display string
}

test "mutant whose tests pass is classified survived" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readTarget(a);
    const res = try classify(a, src, "+", .created, &.{"zig build test"}, &.{outcome(0, false, false)});
    try expectEqual(report.ResultStatus.survived, res.status);
}

fn commandWithKind(status: report.CommandStatus, kind: report.FailureKind) report.CommandResult {
    return .{
        .command = .{ .original = "zig build test", .argv = &.{ "zig", "build", "test" }, .cwd = "<project>" },
        .phase = .mutant,
        .status = status,
        .exit_code = if (status == .failed) 1 else null,
        .timed_out = false,
        .failure_kind = kind,
        .duration_ms = 0,
        .evidence = .{},
        .skip_reason = null,
    };
}

test "compile-error command is compile_error; test failure is killed (failure_kind distinguishes)" {
    // A non-zero exit caused by a compile error classifies as compile_error,
    // while a non-zero exit caused by a test/assertion failure classifies as
    // killed; the difference is the command result's failure_kind, not a single
    // non-zero exit bucket (I-010).
    const compile = mutant_runner.classifyFromCommands("m_demo", .Debug, &.{commandWithKind(.failed, .compile_error)});
    try expectEqual(report.ResultStatus.compile_error, compile.status);
    const killed = mutant_runner.classifyFromCommands("m_demo", .Debug, &.{commandWithKind(.failed, .test_failure)});
    try expectEqual(report.ResultStatus.killed, killed.status);
}

test "mutant compiler crash is compiler_crash, not compile_error or invalid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readTarget(a);
    const res = try classify(a, src, "+", .created, &.{"zig build test"}, &.{outcome(null, false, true)});
    try expectEqual(report.ResultStatus.compiler_crash, res.status);
}

test "mutant timeout is classified timeout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readTarget(a);
    const res = try classify(a, src, "+", .created, &.{"zig build test"}, &.{outcome(null, true, false)});
    try expectEqual(report.ResultStatus.timeout, res.status);
}

test "invalid patch is classified invalid with sandbox classifier source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readTarget(a);
    // original "X" does not match the source at the span -> sandbox patch mismatch.
    const res = try classify(a, src, "X", .created, &.{"zig build test"}, &.{});
    try expectEqual(report.ResultStatus.invalid, res.status);
    try expect(res.classifier_source == .sandbox_validation);
    try expect(std.mem.startsWith(u8, res.evidence.failure_summary, "sandbox:"));
}

test "workspace creation failure is classified invalid (F-010)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readTarget(a);
    const res = try classify(a, src, "+", .create_failed, &.{"zig build test"}, &.{});
    try expectEqual(report.ResultStatus.invalid, res.status);
    try expect(res.classifier_source == .sandbox_validation);
    try expect(std.mem.indexOf(u8, res.evidence.failure_summary, "workspace") != null);
}

test "fail-fast records later commands as skipped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readTarget(a);
    // First command kills; the second must be recorded as skipped, not executed.
    const res = try classify(a, src, "+", .created, &.{ "zig build test", "zig test src/main.zig" }, &.{outcome(1, false, false)});
    try expectEqual(report.ResultStatus.killed, res.status);
    try expectEqual(@as(usize, 2), res.commands.len);
    try expectEqual(report.CommandStatus.failed, res.commands[0].status);
    try expectEqual(report.CommandStatus.skipped, res.commands[1].status);
    try expect(res.commands[1].skip_reason != null);
    try expect(res.commands[1].skip_reason.?.len > 0);
}
