const std = @import("std");
const zentinel = @import("zentinel");
const runner = zentinel.doctest.runner;
const workspace = zentinel.doctest.workspace;
const case = zentinel.doctest.case;
const proc = zentinel.runner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const ws_root = workspace.root ++ "/";

fn mkCase(kind: case.CaseKind, id: []const u8) case.Case {
    return .{
        .id = id,
        .file = "doc.md",
        .kind = kind,
        .label = null,
        .source_ref = "doc.md:1",
        .block_refs = &.{"doc.md:1"},
        .line_start = 1,
        .line_end = 3,
        .anchor_line = 1,
    };
}

const MockExec = struct {
    out: proc.RawOutcome,
    fn run(ctx: *anyopaque, argv: []const []const u8) proc.RawOutcome {
        _ = argv;
        const self: *MockExec = @ptrCast(@alignCast(ctx));
        return self.out;
    }
    fn executor(self: *MockExec) proc.Executor {
        return .{ .ctx = self, .runFn = run };
    }
};

const MockProvider = struct {
    last_dir: []const u8 = "",
    confined: bool = true,
    calls: usize = 0,
    /// When true, materialize reports a workspace-creation failure (models a
    /// transient/environmental createDirPath/writeFile error for one case).
    fail: bool = false,
    fn materialize(ctx: *anyopaque, plan: workspace.Plan) workspace.MaterializeError!void {
        const self: *MockProvider = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        if (self.fail) return error.WorkspaceCreateFailed;
        self.last_dir = plan.dir;
        self.confined = workspace.isConfined(plan);
    }
    fn provider(self: *MockProvider) workspace.Provider {
        return .{ .ctx = self, .materializeFn = materialize };
    }
};

fn outcomeWith(exit_code: ?i64, timed_out: bool, crashed: bool, stdout: []const u8, stderr: []const u8) proc.RawOutcome {
    return .{ .exit_code = exit_code, .timed_out = timed_out, .crashed = crashed, .duration_ms = 1, .stdout = stdout, .stderr = stderr };
}

fn outcome(exit_code: ?i64, timed_out: bool, crashed: bool) proc.RawOutcome {
    return outcomeWith(exit_code, timed_out, crashed, "", "");
}

fn ctxWith(a: std.mem.Allocator, exec: *MockExec, prov: *MockProvider) runner.Context {
    return .{ .arena = a, .root = ".", .zig_version = "0.16.0", .executor = exec.executor(), .provider = prov.provider() };
}

const valid_config = "[project]\nname = \"demo\"\n\n[test]\ncommands = [\"zig build test\"]\n";
const invalid_config = "[project]\nbogus = \"x\"\n";

fn mkResult(status: runner.Status) runner.CaseResult {
    return .{
        .id = "dt_x",
        .kind = .zig_test,
        .status = status,
        .command = null,
        .argv = null,
        .exit_code = null,
        .timed_out = false,
        .stdout_excerpt = "",
        .stderr_excerpt = "",
        .skip_reason = null,
        .diagnostics = &.{},
    };
}

test "zig compile-pass case passes on a clean compile" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{};
    const r = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.zig_compile_pass, "dt_a"), "const x: u8 = 1;\n");
    try expectEqual(runner.Status.passed, r.status);
    try expect(prov.calls == 1); // a workspace was generated
}

test "zig test case passes on exit 0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{};
    const r = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.zig_test, "dt_b"), "test {}\n");
    try expectEqual(runner.Status.passed, r.status);
}

test "zig compile-fail case passes (expected_compile_error) on non-zero compiler exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = MockExec{ .out = outcome(1, false, false) };
    var prov = MockProvider{};
    const r = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.zig_compile_fail, "dt_c"), "pub fn f() void { return 1; }\n");
    try expectEqual(runner.Status.expected_compile_error, r.status);
    // A compile-fail case that actually compiles is a failure.
    var exec_ok = MockExec{ .out = outcome(0, false, false) };
    var prov2 = MockProvider{};
    const r2 = try runner.runCase(ctxWith(arena.allocator(), &exec_ok, &prov2), mkCase(.zig_compile_fail, "dt_c"), "pub fn f() void {}\n");
    try expectEqual(runner.Status.failed, r2.status);
}

test "cli case passes on exit 0 and captures argv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{};
    const r = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.cli, "dt_d"), "zentinel --help");
    try expectEqual(runner.Status.passed, r.status);
    try expectEqualStrings("zentinel --help", r.command.?);
    try expectEqual(@as(usize, 2), r.argv.?.len);
    try expectEqualStrings("zentinel", r.argv.?[0]);
    try expectEqual(@as(?i64, 0), r.exit_code);
    try expect(prov.calls == 0); // cli cases do not generate a Zig workspace
}

test "config case passes on a valid config; config-fail case passes on an invalid config" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{};

    const ok = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.config, "dt_e"), valid_config);
    try expectEqual(runner.Status.passed, ok.status);

    const ok_fail = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.config_fail, "dt_f"), invalid_config);
    try expectEqual(runner.Status.passed, ok_fail.status);

    // A config case with an invalid config fails; a config-fail case with a
    // valid config fails.
    const bad = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.config, "dt_e"), invalid_config);
    try expectEqual(runner.Status.failed, bad.status);
    const bad_fail = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.config_fail, "dt_f"), valid_config);
    try expectEqual(runner.Status.failed, bad_fail.status);
}

test "timeout outcome yields timeout status with a null exit code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = MockExec{ .out = outcome(null, true, false) };
    var prov = MockProvider{};
    const r = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.zig_test, "dt_g"), "test {}\n");
    try expectEqual(runner.Status.timeout, r.status);
    try expect(r.timed_out);
    try expectEqual(@as(?i64, null), r.exit_code);
}

test "doctest output excerpts are bounded on UTF-8 codepoint boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const big = try a.alloc(u8, proc.excerpt_limit + 2);
    @memset(big[0 .. proc.excerpt_limit - 1], 'x');
    @memcpy(big[proc.excerpt_limit - 1 .. proc.excerpt_limit + 2], "€");

    var exec = MockExec{ .out = outcomeWith(0, false, false, big, big) };
    var prov = MockProvider{};
    const r = try runner.runCase(ctxWith(a, &exec, &prov), mkCase(.cli, "dt_utf8"), "zentinel --help");
    try expectEqual(runner.Status.passed, r.status);
    try expectEqual(@as(usize, proc.excerpt_limit - 1), r.stdout_excerpt.len);
    try expect(std.unicode.utf8ValidateSlice(r.stdout_excerpt));
    try expect(std.unicode.utf8ValidateSlice(r.stderr_excerpt));
}

test "unsupported CLI command is rejected with ZNTL_DOCTEST_COMMAND_REJECTED" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{};

    // Non-zentinel command.
    const r = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.cli, "dt_h"), "git status");
    try expectEqual(runner.Status.invalid, r.status);
    try expectEqual(@as(usize, 1), r.diagnostics.len);
    try expectEqualStrings(runner.command_rejected_code, r.diagnostics[0].code);

    // Shell metacharacter (pipe).
    const r2 = try runner.runCase(ctxWith(arena.allocator(), &exec, &prov), mkCase(.cli, "dt_h"), "zentinel run | cat");
    try expectEqual(runner.Status.invalid, r2.status);
    try expectEqualStrings(runner.command_rejected_code, r2.diagnostics[0].code);
}

test "a per-case workspace-creation failure isolates that case as invalid, not a run-wide abort" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A transient/environmental workspace-create failure for ONE Zig case must
    // isolate to that case (status .invalid + a workspace diagnostic), symmetric
    // with the mutation path (mutant_runner folds create_failed into an `invalid`
    // mutant). Previously runZig propagated WorkspaceCreateFailed with `try`, so
    // the first failing case aborted the whole doctest run (exit 4, no report),
    // discarding every other case's verdict.
    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{ .fail = true };
    const r = try runner.runCase(ctxWith(a, &exec, &prov), mkCase(.zig_test, "dt_ws"), "test {}\n");
    try expectEqual(runner.Status.invalid, r.status);
    try expectEqual(@as(usize, 1), r.diagnostics.len);
    try expectEqualStrings(runner.workspace_failed_code, r.diagnostics[0].code);
    try expect(prov.calls == 1); // materialize was attempted before the failure
    // The case-level fields are inert for an isolated workspace failure.
    try expectEqual(@as(?i64, null), r.exit_code);
    try expect(!r.timed_out);
}

test "ordinary failure statuses exit 1; expected_compile_error is a successful compile-fail status" {
    // passed / skipped / expected_compile_error are successful.
    try expectEqual(@as(u8, 0), runner.exitCode(&.{ mkResult(.passed), mkResult(.expected_compile_error), mkResult(.skipped) }));
    // expected_compile_error alone is success.
    try expectEqual(@as(u8, 0), runner.exitCode(&.{mkResult(.expected_compile_error)}));
    // Every other ordinary status forces exit 1.
    inline for (.{ runner.Status.failed, runner.Status.compile_error, runner.Status.timeout, runner.Status.invalid }) |st| {
        try expectEqual(@as(u8, 1), runner.exitCode(&.{mkResult(st)}));
    }
    // One failure among passes still exits 1.
    try expectEqual(@as(u8, 1), runner.exitCode(&.{ mkResult(.passed), mkResult(.failed) }));
}

test "property: workspace path is stable for the same case hash and varies with content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const d1 = try workspace.workspaceDir(a, "dt_x", "const x = 1;\n", "0.16.0");
    const d2 = try workspace.workspaceDir(a, "dt_x", "const x = 1;\n", "0.16.0");
    try expectEqualStrings(d1, d2);

    const d3 = try workspace.workspaceDir(a, "dt_x", "const x = 2;\n", "0.16.0");
    try expect(!std.mem.eql(u8, d1, d3));

    const d4 = try workspace.workspaceDir(a, "dt_x", "const x = 1;\n", "0.17.0");
    try expect(!std.mem.eql(u8, d1, d4));
}

test "property: a Zig case only ever materializes a confined workspace (repo files untouched)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const plan = try workspace.zigPlan(a, "dt_x", "const x = 1;\n", "0.16.0");
    try expect(workspace.isConfined(plan));
    try expect(std.mem.startsWith(u8, plan.dir, ws_root));
    try expect(std.mem.startsWith(u8, plan.files[0].rel_path, ws_root));

    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{};
    _ = try runner.runCase(ctxWith(a, &exec, &prov), mkCase(.zig_compile_pass, "dt_x"), "const x = 1;\n");
    try expect(prov.confined);
    try expect(std.mem.startsWith(u8, prov.last_dir, ws_root));
}

test "property: repeated execution of the same case produces an equivalent status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{};
    const r1 = try runner.runCase(ctxWith(a, &exec, &prov), mkCase(.zig_test, "dt_x"), "test {}\n");
    const r2 = try runner.runCase(ctxWith(a, &exec, &prov), mkCase(.zig_test, "dt_x"), "test {}\n");
    try expectEqual(r1.status, r2.status);
    try expectEqualStrings(r1.id, r2.id);
}

test "property: CLI command parsing rejects shell metacharacter variants consistently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var exec = MockExec{ .out = outcome(0, false, false) };
    var prov = MockProvider{};

    const rejected = [_][]const u8{
        "zentinel run | cat",
        "zentinel a; rm",
        "zentinel a && b",
        "zentinel $(echo x)",
        "zentinel run > out.txt",
        "zentinel run < in.txt",
        "zentinel `whoami`",
        "git status", // not zentinel
    };
    for (rejected) |cmd| {
        const r = try runner.runCase(ctxWith(a, &exec, &prov), mkCase(.cli, "dt_x"), cmd);
        try expectEqual(runner.Status.invalid, r.status);
        try expect(r.diagnostics.len == 1);
        try expectEqualStrings(runner.command_rejected_code, r.diagnostics[0].code);
    }
}
