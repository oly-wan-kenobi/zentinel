// Layer: deterministic_core
//
// Normal doctest execution for Zig, CLI, and config cases (docs/DOCTEST_SPEC.md,
// docs/DOCTEST_ARCHITECTURE.md "Execution Strategy"). No mutation support, no
// snapshot matching, no cache. Status is determined only by deterministic
// execution: Zig/CLI cases run their command through the shared injected
// `Executor` (the real process spawner is wired by the CLI; tests inject a
// mock), config cases validate through the in-tree config parser (no process).
// CLI examples may only invoke `zentinel` and must parse as shell-free argv, or
// they are rejected with ZNTL_DOCTEST_COMMAND_REJECTED. Workspaces are generated
// through the injected workspace provider; repository files are never modified.
const std = @import("std");
const case = @import("case.zig");
const workspace = @import("workspace.zig");
const proc = @import("../runner.zig");
const command = @import("../command.zig");
const config = @import("../config.zig");

/// Public doctest-policy diagnostic for a CLI doctest command that is not an
/// allowed `zentinel` shell-free invocation (docs/ERROR_CODES.md). The parser's
/// ZNTL_DOCTEST_* codes live in src/error_codes.zig; this command-policy code is
/// owned by the runner that enforces it.
pub const command_rejected_code = "ZNTL_DOCTEST_COMMAND_REJECTED";

/// Ordinary doctest statuses (docs/DOCTEST_SPEC.md). `expected_compile_error` is
/// a pass status for `zig compile_fail` only.
pub const Status = enum {
    passed,
    failed,
    compile_error,
    expected_compile_error,
    timeout,
    skipped,
    invalid,

    pub fn toString(self: Status) []const u8 {
        return @tagName(self);
    }
};

pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
};

pub const CaseResult = struct {
    id: []const u8,
    kind: case.CaseKind,
    status: Status,
    /// Original command string when a command was executed, else null.
    command: ?[]const u8,
    argv: ?[]const []const u8,
    /// Process exit code; null on timeout/abnormal termination or non-command cases.
    exit_code: ?i64,
    timed_out: bool,
    stdout_excerpt: []const u8,
    stderr_excerpt: []const u8,
    /// Skip reason for skipped cases, else null.
    skip_reason: ?[]const u8,
    diagnostics: []const Diagnostic,
};

pub const Context = struct {
    arena: std.mem.Allocator,
    /// Project root / cwd label recorded in evidence.
    root: []const u8,
    zig_version: []const u8,
    executor: proc.Executor,
    provider: workspace.Provider,
};

pub const RunError = workspace.MaterializeError;

/// 1 if any case has a status other than passed/skipped/expected_compile_error,
/// else 0 (docs/DOCTEST_SPEC.md exit semantics). Invalid CLI/selector usage
/// (exit 2) and internal errors (exit 4) are handled at the CLI layer.
pub fn exitCode(results: []const CaseResult) u8 {
    for (results) |r| {
        switch (r.status) {
            .passed, .skipped, .expected_compile_error => {},
            else => return 1,
        }
    }
    return 0;
}

pub fn runCase(ctx: Context, c: case.Case, content: []const u8) RunError!CaseResult {
    return switch (c.kind) {
        .config => runConfig(ctx, c, content, true),
        .config_fail => runConfig(ctx, c, content, false),
        .cli => runCli(ctx, c, content),
        .zig_compile_pass => runZig(ctx, c, content, .compile_pass),
        .zig_test => runZig(ctx, c, content, .zig_test),
        .zig_compile_fail => runZig(ctx, c, content, .compile_fail),
        // Mutation cases are validated only by `zentinel doctest --mutate`.
        .mutation => skipped(ctx, c, "mutation cases require doctest --mutate"),
    };
}

fn runConfig(ctx: Context, c: case.Case, content: []const u8, expect_pass: bool) RunError!CaseResult {
    var diag: config.Diagnostic = .{};
    const valid = if (config.load(ctx.arena, content, &diag)) |_| true else |err| switch (err) {
        error.Invalid => false,
        error.OutOfMemory => return error.OutOfMemory,
    };
    const status: Status = if (valid == expect_pass) .passed else .failed;
    // On a validation failure, surface the deterministic config diagnostic as the
    // case output so a `text output` expectation block can verify the documented
    // reason. A valid config has no diagnostic.
    const out: []const u8 = if (valid) "" else try std.fmt.allocPrint(ctx.arena, "error[{s}]: {s}", .{ diag.code.token(), diag.message });
    return base(c, status, null, null, null, false, out, "", null, &.{});
}

fn runCli(ctx: Context, c: case.Case, content: []const u8) RunError!CaseResult {
    // A CLI doctest is a single command line; fenced block content carries a
    // trailing newline that is not an argv delimiter, so trim it first.
    const cmd_line = std.mem.trim(u8, content, " \t\r\n");
    const parsed = try command.parse(ctx.arena, cmd_line);
    const argv = switch (parsed) {
        .ok => |a| a,
        .invalid => return rejected(ctx, c, cmd_line, "doctest CLI command is not valid shell-free argv"),
    };
    if (argv.len == 0 or !std.mem.eql(u8, argv[0], "zentinel")) {
        return rejected(ctx, c, content, "doctest CLI command must invoke zentinel");
    }
    const raw = ctx.executor.run(argv);
    const status = classifyCommand(raw);
    return base(
        c,
        status,
        cmd_line,
        argv,
        if (raw.timed_out or raw.crashed) null else raw.exit_code,
        raw.timed_out,
        try bounded(ctx.arena, raw.stdout),
        try bounded(ctx.arena, raw.stderr),
        null,
        &.{},
    );
}

const ZigMode = enum { compile_pass, zig_test, compile_fail };

fn runZig(ctx: Context, c: case.Case, content: []const u8, mode: ZigMode) RunError!CaseResult {
    const plan = try workspace.zigPlan(ctx.arena, c.id, content, ctx.zig_version);
    try ctx.provider.materialize(plan);

    const src = plan.files[0].rel_path;
    const argv = try ctx.arena.dupe([]const u8, &.{ "zig", "test", src });
    const raw = ctx.executor.run(argv);
    const status = classifyZig(raw, mode);
    return base(
        c,
        status,
        null,
        argv,
        if (raw.timed_out or raw.crashed) null else raw.exit_code,
        raw.timed_out,
        try bounded(ctx.arena, raw.stdout),
        try bounded(ctx.arena, raw.stderr),
        null,
        &.{},
    );
}

fn classifyCommand(raw: proc.RawOutcome) Status {
    if (raw.timed_out) return .timeout;
    if (raw.crashed) return .failed;
    if (raw.exit_code) |code| return if (code == 0) .passed else .failed;
    return .failed;
}

fn classifyZig(raw: proc.RawOutcome, mode: ZigMode) Status {
    if (raw.timed_out) return .timeout;
    switch (mode) {
        .compile_fail => {
            if (raw.crashed) return .compile_error;
            if (raw.exit_code) |code| return if (code != 0) .expected_compile_error else .failed;
            return .compile_error;
        },
        .compile_pass => {
            if (raw.crashed) return .compile_error;
            if (raw.exit_code) |code| return if (code == 0) .passed else .compile_error;
            return .compile_error;
        },
        .zig_test => {
            if (raw.crashed) return .compile_error;
            if (raw.exit_code) |code| return if (code == 0) .passed else .failed;
            return .failed;
        },
    }
}

fn rejected(ctx: Context, c: case.Case, content: []const u8, message: []const u8) RunError!CaseResult {
    const diags = try ctx.arena.dupe(Diagnostic, &.{.{ .code = command_rejected_code, .message = message }});
    return base(c, .invalid, content, null, null, false, "", "", null, diags);
}

fn skipped(ctx: Context, c: case.Case, reason: []const u8) RunError!CaseResult {
    _ = ctx;
    return base(c, .skipped, null, null, null, false, "", "", reason, &.{});
}

fn base(
    c: case.Case,
    status: Status,
    cmd: ?[]const u8,
    argv: ?[]const []const u8,
    exit_code: ?i64,
    timed_out: bool,
    stdout_excerpt: []const u8,
    stderr_excerpt: []const u8,
    skip_reason: ?[]const u8,
    diagnostics: []const Diagnostic,
) CaseResult {
    return .{
        .id = c.id,
        .kind = c.kind,
        .status = status,
        .command = cmd,
        .argv = argv,
        .exit_code = exit_code,
        .timed_out = timed_out,
        .stdout_excerpt = stdout_excerpt,
        .stderr_excerpt = stderr_excerpt,
        .skip_reason = skip_reason,
        .diagnostics = diagnostics,
    };
}

fn bounded(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    const len = proc.utf8BoundaryLen(text, proc.excerpt_limit);
    return arena.dupe(u8, text[0..len]);
}
