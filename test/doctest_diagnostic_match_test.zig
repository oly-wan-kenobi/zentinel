// Regression tests for the doctest false-pass cluster: compiler/diagnostic
// expectations must be matched against stderr (not the empty stdout), a
// non-matching expected diagnostic must demote a compile-fail case instead of
// staying green, `diagnostic expected` blocks must be recognized, every
// expectation block of a case must be checked, and `regex` match mode must work.
const std = @import("std");
const zentinel = @import("zentinel");
const dc = zentinel.doctest_command;
const dreport = zentinel.doctest.report;
const workspace = zentinel.doctest.workspace;
const proc = zentinel.runner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// A fixed-outcome executor: every spawned command returns the same canned
// stdout/stderr/exit, so a test can control exactly which stream carries which
// text and assert the matcher reads the right one.
const FixedExec = struct {
    exit_code: ?i64,
    stdout: []const u8,
    stderr: []const u8,
    fn run(ctx: *anyopaque, argv: []const []const u8) proc.RawOutcome {
        _ = argv;
        const self: *FixedExec = @ptrCast(@alignCast(ctx));
        return .{ .exit_code = self.exit_code, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = self.stdout, .stderr = self.stderr };
    }
};

const NoopProvider = struct {
    fn materialize(ctx: *anyopaque, plan: workspace.Plan) workspace.MaterializeError!void {
        _ = ctx;
        _ = plan;
    }
};

fn depsWith(exec: *FixedExec) dc.Deps {
    return .{
        .executor = .{ .ctx = exec, .runFn = FixedExec.run },
        .provider = .{ .ctx = undefined, .materializeFn = NoopProvider.materialize },
    };
}

fn obs() dc.Observation {
    return .{
        .run_id = "doctest_run_diag",
        .started_at = "2026-06-03T00:00:00Z",
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .project_root = ".",
        .command = "zentinel doctest",
    };
}

fn runSource(a: std.mem.Allocator, src: []const u8, exec: *FixedExec) !dc.Output {
    return dc.run(a, .{ .file = "x.md" }, "x.md", src, obs(), depsWith(exec));
}

fn firstCase(out: dc.Output) dreport.Case {
    return out.report.cases[0];
}

// A compile-fail producer followed by a `diagnostic expected` block.
const compile_fail_diag =
    \\Example.
    \\
    \\```zig compile_fail
    \\export fn f() void { return 1; }
    \\```
    \\
    \\```diagnostic expected
    \\error: expected type 'void'
    \\```
    \\
;

test "compile_fail diagnostic matches against stderr and passes (expected_compile_error)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // The compiler diagnostic is on stderr (where zig writes errors); stdout empty.
    var exec = FixedExec{ .exit_code = 1, .stdout = "", .stderr = "src/x.zig:1:34: error: expected type 'void', found 'comptime_int'\n" };
    const out = try runSource(arena.allocator(), compile_fail_diag, &exec);
    try expectEqual(dreport.Status.expected_compile_error, firstCase(out).status);
    try expectEqual(@as(u8, 0), out.exit_code);
}

test "compile_fail with a non-matching expected diagnostic demotes to compile_error (no false pass)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Real error is a different one: the documented diagnostic no longer holds.
    var exec = FixedExec{ .exit_code = 1, .stdout = "", .stderr = "src/x.zig:1:1: error: unused function parameter\n" };
    const out = try runSource(arena.allocator(), compile_fail_diag, &exec);
    try expectEqual(dreport.Status.compile_error, firstCase(out).status);
    try expectEqual(@as(u8, 1), out.exit_code);
    try expect(firstCase(out).result.?.snapshot != null);
    try expect(!firstCase(out).result.?.snapshot.?.matched);
    try expectEqual(dreport.ActualRef.diagnostic, firstCase(out).result.?.snapshot.?.actual_ref);
}

test "compile_fail diagnostic is NOT vacuously satisfied by matching text on the empty stdout" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Put the expected text only on stdout; stderr carries the real (different)
    // error. Pre-fix, matching stdout would pass; post-fix we match stderr -> fail.
    var exec = FixedExec{ .exit_code = 1, .stdout = "error: expected type 'void'\n", .stderr = "src/x.zig:1:1: error: something unrelated\n" };
    const out = try runSource(arena.allocator(), compile_fail_diag, &exec);
    try expectEqual(dreport.Status.compile_error, firstCase(out).status);
}

// Two expectation blocks on one CLI case; the SECOND one must also be checked.
const cli_two_expectations =
    \\```bash cli
    \\zentinel version
    \\```
    \\
    \\```text output contains
    \\zentinel
    \\```
    \\
    \\```text output contains
    \\NOPE-not-in-output
    \\```
    \\
;

test "every expectation block is matched; a mismatching second block fails the case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = FixedExec{ .exit_code = 0, .stdout = "zentinel 0.0.0\n", .stderr = "" };
    const out = try runSource(arena.allocator(), cli_two_expectations, &exec);
    try expectEqual(dreport.Status.failed, firstCase(out).status);
    try expectEqual(@as(u8, 1), out.exit_code);
}

// A CLI case whose output is matched by a regex expectation.
const cli_regex =
    \\```bash cli
    \\zentinel version
    \\```
    \\
    \\```text output regex
    \\zentinel [0-9]+\.[0-9]+\.[0-9]+
    \\```
    \\
;

test "regex match mode is wired and matches the actual output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = FixedExec{ .exit_code = 0, .stdout = "zentinel 0.0.0\n", .stderr = "" };
    const out = try runSource(arena.allocator(), cli_regex, &exec);
    try expectEqual(dreport.Status.passed, firstCase(out).status);
    try expectEqual(dreport.MatchMode.regex, firstCase(out).result.?.snapshot.?.match_mode);
}
