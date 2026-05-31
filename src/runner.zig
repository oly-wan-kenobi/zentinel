// Layer: deterministic_core
//
// Baseline test-command runner (docs/REPORT_FORMAT.md, docs/SANDBOX_SECURITY.md).
// The runner parses configured command strings into argv with the shared
// src/command.zig parser, executes them through an injected `Executor`
// abstraction, and deterministically classifies each result and the overall
// baseline status. Process spawning itself is a side_effect_adapter concern: the
// real `Executor` is wired by the run command / binary, while unit tests inject
// a deterministic mock. This keeps classification pure and testable through the
// deterministic-core hub without depending on machine-specific commands.
const std = @import("std");
const command = @import("command.zig");
const report = @import("report.zig");

/// Bound for normalized command output excerpts (docs/SANDBOX_SECURITY.md).
pub const excerpt_limit = 4096;

/// Raw outcome of executing one command, produced by an injected `Executor`.
/// `exit_code` is null on timeout or abnormal termination.
pub const RawOutcome = struct {
    exit_code: ?i64,
    timed_out: bool,
    crashed: bool,
    duration_ms: u64,
    stdout: []const u8,
    stderr: []const u8,
};

/// Command execution abstraction. The runner never spawns processes directly;
/// the production executor (std.process-based, side_effect_adapter) is injected
/// by the run command, and tests inject a deterministic mock.
pub const Executor = struct {
    ctx: *anyopaque,
    runFn: *const fn (ctx: *anyopaque, argv: []const []const u8) RawOutcome,

    pub fn run(self: Executor, argv: []const []const u8) RawOutcome {
        return self.runFn(self.ctx, argv);
    }
};

pub const BaselineError = error{InvalidCommand} || std.mem.Allocator.Error;

pub const BaselineResult = struct {
    status: report.BaselineStatus,
    commands: []const report.CommandResult,
};

/// Public ZNTL diagnostic code for a non-passed baseline command status
/// (docs/ERROR_CODES.md). Returns "" for a passed command.
pub fn statusCode(status: report.CommandStatus) []const u8 {
    return switch (status) {
        .passed => "",
        .failed => "ZNTL_RUNNER_COMMAND_FAILED",
        .timeout => "ZNTL_RUNNER_TIMEOUT",
        .compiler_crash => "ZNTL_RUNNER_COMPILER_CRASH",
        .skipped => "",
    };
}

/// Normalize then bound a captured command-output excerpt. Normalization happens
/// BEFORE truncation so the cut point is itself deterministic: ASLR addresses of
/// different widths would otherwise shift the truncation boundary between runs.
/// The normalizer (report.normalizeExcerpt) replaces hex pointer addresses and
/// absolute machine paths with stable placeholders so repeated runs over the same
/// project produce identical excerpts (docs/REPORT_FORMAT.md).
fn boundedExcerpt(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    const normalized = try report.normalizeExcerpt(arena, text);
    const len = @min(normalized.len, excerpt_limit);
    return normalized[0..len];
}

/// Classify one raw outcome into a `CommandResult` for the given phase. Status is
/// derived only from the command outcome (runner evidence authority, I-001); AI
/// cannot influence it. Reused for baseline and mutant command classification.
pub fn classifyCommand(
    arena: std.mem.Allocator,
    phase: report.Phase,
    original: []const u8,
    argv: []const []const u8,
    cwd: []const u8,
    raw: RawOutcome,
) std.mem.Allocator.Error!report.CommandResult {
    var status: report.CommandStatus = .passed;
    var failure_kind: report.FailureKind = .none;
    var exit_code: ?i64 = raw.exit_code;

    if (raw.timed_out) {
        status = .timeout;
        failure_kind = .timeout;
        exit_code = null;
    } else if (raw.crashed) {
        status = .compiler_crash;
        failure_kind = .compiler_crash;
        exit_code = null;
    } else if (raw.exit_code) |code| {
        if (code == 0) {
            status = .passed;
            failure_kind = .none;
        } else {
            status = .failed;
            failure_kind = .test_failure;
        }
    } else {
        // No exit code without timeout/crash: treat as a command failure.
        status = .failed;
        failure_kind = .test_failure;
    }

    const failure_summary: []const u8 = if (status == .passed) "" else statusCode(status);

    return .{
        .command = .{
            .original = original,
            .argv = argv,
            .cwd = cwd,
            .environment_policy = .minimal,
            .shell = false,
        },
        .phase = phase,
        .status = status,
        .exit_code = exit_code,
        .timed_out = raw.timed_out,
        .failure_kind = failure_kind,
        .duration_ms = raw.duration_ms,
        .evidence = .{
            .stdout_excerpt = try boundedExcerpt(arena, raw.stdout),
            .stderr_excerpt = try boundedExcerpt(arena, raw.stderr),
            .failure_summary = failure_summary,
        },
        .skip_reason = null,
    };
}

/// Run each configured command in order through `executor`, classify it, and
/// derive the baseline status. The baseline passes only if every command passed;
/// any failure, timeout, or compiler crash is a baseline failure (which blocks
/// later mutation execution at the run/report layer).
pub fn runBaseline(
    arena: std.mem.Allocator,
    executor: Executor,
    commands: []const []const u8,
    cwd: []const u8,
) BaselineError!BaselineResult {
    var results: std.ArrayList(report.CommandResult) = .empty;
    for (commands) |original| {
        const parsed = try command.parse(arena, original);
        const argv = switch (parsed) {
            .ok => |a| a,
            .invalid => return error.InvalidCommand,
        };
        const raw = executor.run(argv);
        const result = try classifyCommand(arena, .baseline, original, argv, cwd, raw);
        try results.append(arena, result);
        // Fail-fast: a non-passing baseline command blocks the whole run, so the
        // remaining baseline commands are not executed. Baseline commands are
        // never recorded as `skipped` (report invariant), so the run shortens by
        // truncation -- only the executed prefix ending at the failure is kept.
        if (result.status != .passed) {
            return .{ .status = .failed, .commands = try results.toOwnedSlice(arena) };
        }
    }
    return .{
        .status = .passed,
        .commands = try results.toOwnedSlice(arena),
    };
}
