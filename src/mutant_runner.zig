// Layer: deterministic_core
//
// Mutant runner (docs/REPORT_FORMAT.md, docs/INTERNAL_API_CONTRACTS.md): combines
// the mutant model, the patch sandbox, and the runner to run one patched mutant
// and classify its result (killed/survived/compile_error/compiler_crash/timeout/
// invalid). Status is derived only from command results and patch validity
// (classifier_source names the deterministic authority); AI cannot modify it.
// Filesystem workspace creation and process spawning are injected (a
// WorkspaceOutcome and a runner.Executor) so classification stays pure and
// testable; the production providers perform the side effects.
const std = @import("std");
const mutant = @import("mutant.zig");
const sandbox = @import("sandbox.zig");
const runner = @import("runner.zig");
const report = @import("report.zig");
const command = @import("command.zig");

/// The deterministic authority that produced a mutant result. Internal evidence
/// for report construction; never populated from AI output.
pub const ClassifierSource = enum {
    runner_command_evidence,
    patch_validation,
    sandbox_validation,
    backend_contract_validation,
    skip_policy,
};

pub const MutationResult = struct {
    mutant_id: []const u8,
    status: report.ResultStatus,
    mode: report.Mode,
    classifier_source: ClassifierSource,
    commands: []const report.CommandResult,
    evidence: report.Evidence,
    skip_reason: ?[]const u8,
};

/// Outcome of creating the per-mutant filesystem workspace (F-010). Injected so
/// the runner is testable; the production provider performs filesystem I/O.
pub const WorkspaceOutcome = enum { created, create_failed };

/// Map one mutant command result to a terminal mutant status, or null if the
/// command passed or was skipped. `failure_kind` distinguishes a compile error
/// (compile_error) from a test/assertion failure (killed) so a single non-zero
/// exit is not collapsed into one bucket (I-010).
fn terminalStatus(c: report.CommandResult) ?report.ResultStatus {
    return switch (c.status) {
        .passed, .skipped => null,
        .failed => if (c.failure_kind == .compile_error) .compile_error else .killed,
        .timeout => .timeout,
        .compiler_crash => .compiler_crash,
    };
}

/// Classify a mutant from its command results: the first terminal command status
/// in order, or `survived` if every command passed. Pure.
pub fn classifyFromCommands(mutant_id: []const u8, mode: report.Mode, commands: []const report.CommandResult) MutationResult {
    var status: report.ResultStatus = .survived;
    for (commands) |c| {
        if (terminalStatus(c)) |terminal| {
            status = terminal;
            break;
        }
    }
    return .{
        .mutant_id = mutant_id,
        .status = status,
        .mode = mode,
        .classifier_source = .runner_command_evidence,
        .commands = commands,
        .evidence = .{},
        .skip_reason = null,
    };
}

fn invalidResult(mutant_id: []const u8, mode: report.Mode, summary: []const u8) MutationResult {
    return .{
        .mutant_id = mutant_id,
        .status = .invalid,
        .mode = mode,
        .classifier_source = .sandbox_validation,
        .commands = &.{},
        .evidence = .{ .failure_summary = summary },
        .skip_reason = null,
    };
}

fn skippedCommand(arena: std.mem.Allocator, original: []const u8, cwd: []const u8) std.mem.Allocator.Error!report.CommandResult {
    const argv = switch (try command.parse(arena, original)) {
        .ok => |a| a,
        .invalid => try arena.dupe([]const u8, &.{original}),
    };
    return .{
        .command = .{ .original = original, .argv = argv, .cwd = cwd, .environment_policy = .minimal, .shell = false },
        .phase = .mutant,
        .status = .skipped,
        .exit_code = null,
        .timed_out = false,
        .failure_kind = .skipped,
        .duration_ms = 0,
        .evidence = .{},
        .skip_reason = "fail-fast: an earlier command determined the mutant result",
    };
}

fn skippedCommandSpec(spec: command.Spec, cwd: []const u8) report.CommandResult {
    return .{
        .command = .{ .original = spec.original, .argv = spec.argv, .cwd = cwd, .environment_policy = .minimal, .shell = false },
        .phase = .mutant,
        .status = .skipped,
        .exit_code = null,
        .timed_out = false,
        .failure_kind = .skipped,
        .duration_ms = 0,
        .evidence = .{},
        .skip_reason = "fail-fast: an earlier command determined the mutant result",
    };
}

/// Run one mutant: check workspace creation (F-010), apply the patch (sandbox
/// validation -> `invalid` on span/original failure), run the mutant's commands
/// through the injected executor with fail-fast (later commands recorded as
/// skipped), and classify the result.
pub fn run(
    arena: std.mem.Allocator,
    m: mutant.Mutant,
    source: []const u8,
    workspace: WorkspaceOutcome,
    commands: []const []const u8,
    cwd: []const u8,
    executor: runner.Executor,
    mode: report.Mode,
) std.mem.Allocator.Error!MutationResult {
    var specs: std.ArrayList(command.Spec) = .empty;
    for (commands) |original| {
        const argv = switch (try command.parse(arena, original)) {
            .ok => |a| a,
            .invalid => return invalidResult(m.id, mode, "sandbox: configured command is not valid argv"),
        };
        try specs.append(arena, .{ .original = original, .argv = argv });
    }
    return runSpecs(arena, m, source, workspace, try specs.toOwnedSlice(arena), cwd, executor, mode);
}

/// Run one mutant with already-structured command argv. Used by generated
/// same-file selections so report evidence can keep rendered command text while
/// execution uses exact shell-free argv for filenames that are not valid command
/// language tokens.
pub fn runSpecs(
    arena: std.mem.Allocator,
    m: mutant.Mutant,
    source: []const u8,
    workspace: WorkspaceOutcome,
    commands: []const command.Spec,
    cwd: []const u8,
    executor: runner.Executor,
    mode: report.Mode,
) std.mem.Allocator.Error!MutationResult {
    if (workspace == .create_failed) {
        return invalidResult(m.id, mode, "sandbox: mutation workspace could not be created");
    }
    _ = sandbox.apply(arena, source, m) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SpanOutOfRange => return invalidResult(m.id, mode, sandbox.failureSummary(error.SpanOutOfRange)),
        error.PatchMismatch => return invalidResult(m.id, mode, sandbox.failureSummary(error.PatchMismatch)),
    };

    var results: std.ArrayList(report.CommandResult) = .empty;
    var decided = false;
    for (commands) |spec| {
        if (decided) {
            try results.append(arena, skippedCommandSpec(spec, cwd));
            continue;
        }
        const raw = executor.run(spec.argv);
        const cr = try runner.classifyCommand(arena, .mutant, spec.original, spec.argv, cwd, raw);
        try results.append(arena, cr);
        if (terminalStatus(cr) != null) decided = true;
    }
    return classifyFromCommands(m.id, mode, try results.toOwnedSlice(arena));
}
