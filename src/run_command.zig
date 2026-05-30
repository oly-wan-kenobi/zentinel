// Layer: deterministic_core
//
// `zentinel run` orchestration (docs/CLI_SPEC.md, docs/REPORT_FORMAT.md). Wires
// project model, baseline runner, Phase 1 AST mutators, the patch sandbox, and
// the mutant runner into a single serial flow that produces a deterministic
// report. Pure: process execution and filesystem workspaces are injected (a
// baseline `runner.Executor` and a `MutantRunner`), and source bytes are passed
// in, so the orchestration and report assembly are testable without real
// processes. The presentation adapter wires the real providers for the binary.
const std = @import("std");
const config = @import("config.zig");
const ast_backend = @import("ast_backend.zig");
const mutant = @import("mutant.zig");
const arithmetic = @import("mutators/arithmetic.zig");
const comparison = @import("mutators/comparison.zig");
const logical = @import("mutators/logical.zig");
const boolean = @import("mutators/boolean.zig");
const runner = @import("runner.zig");
const mutant_runner = @import("mutant_runner.zig");
const report = @import("report.zig");

pub const ReportFormat = enum { text, json, jsonl, junit };

pub const Options = struct {
    operator_filter: ?[]const u8 = null,
    mutant_filter: ?[]const u8 = null,
    fail_on_survivors: bool = false,
    report_format: ReportFormat = .text,
    output: ?[]const u8 = null,
    /// Terminal verbosity (docs/CLI_SPEC.md). Affects only the text rendering in
    /// the adapter; never changes deterministic report data.
    verbose: bool = false,
    quiet: bool = false,
};

/// Observation metadata supplied by the caller. Normalized in snapshots/tests.
pub const Observation = struct {
    run_id: []const u8,
    started_at: []const u8,
    project_root: []const u8,
    zentinel_version: []const u8,
    zig_version: []const u8,
    config_hash: []const u8,
    duration_ms: u64 = 0,
};

/// One eligible source file and its bytes (read by the caller).
pub const FileSource = struct {
    path: []const u8,
    source: []const u8,
};

/// Per-mutant execution abstraction. Tests inject a mock returning programmed
/// results; the binary injects a runner that creates a workspace, writes the
/// patched file, runs the configured commands, and classifies.
pub const MutantRunner = struct {
    ctx: *anyopaque,
    runFn: *const fn (ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult,

    pub fn run(self: MutantRunner, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
        return self.runFn(self.ctx, m, source, commands, mode);
    }
};

pub const RunOutcome = struct {
    exit_code: u8,
    report: report.Report,
};

pub const RunError = error{
    JobsNotSupported,
    OutputOutsideRoot,
} || std.mem.Allocator.Error;

pub const ParseError = error{ MissingValue, UnknownOption, InvalidReportFormat };

/// Pure parser for Phase 1 `run` options (the argv following the `run` command).
/// Only documented options are accepted; anything else is a usage error so the
/// adapter can reject it instead of silently ignoring it.
pub fn parseArgs(args: []const []const u8) ParseError!Options {
    var opts: Options = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--fail-on-survivors")) {
            opts.fail_on_survivors = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, arg, "--quiet")) {
            opts.quiet = true;
        } else if (std.mem.eql(u8, arg, "--operator")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.operator_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--mutant")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.mutant_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--report")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            if (std.mem.eql(u8, args[i], "text")) {
                opts.report_format = .text;
            } else if (std.mem.eql(u8, args[i], "json")) {
                opts.report_format = .json;
            } else if (std.mem.eql(u8, args[i], "jsonl")) {
                opts.report_format = .jsonl;
            } else if (std.mem.eql(u8, args[i], "junit")) {
                opts.report_format = .junit;
            } else {
                return error.InvalidReportFormat;
            }
        } else if (std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.output = args[i];
        } else {
            return error.UnknownOption;
        }
    }
    return opts;
}

/// Run the Phase 1 flow and produce a deterministic report plus a process exit
/// code (0 ok, 1 survivors under --fail-on-survivors, 3 baseline failure).
pub fn run(
    arena: std.mem.Allocator,
    cfg: config.Config,
    files: []const FileSource,
    options: Options,
    baseline_executor: runner.Executor,
    mutant_executor: MutantRunner,
    obs: Observation,
) RunError!RunOutcome {
    // Reject not-yet-supported options before doing work.
    if (cfg.run_jobs > 1) return error.JobsNotSupported;
    if (options.output) |out| {
        if (config.isOutsideRoot(out)) return error.OutputOutsideRoot;
    }

    const mode: report.Mode = .Debug; // single-mode until task 058

    // Baseline.
    const baseline = runner.runBaseline(arena, baseline_executor, cfg.test_commands, obs.project_root) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.OutOfMemory, // configured commands are check-validated; treat as fatal
    };

    if (baseline.status != .passed) {
        return .{
            .exit_code = 3,
            .report = .{
                .run = baseRun(obs, .baseline_failed),
                .baseline = .{ .status = .failed, .commands = baseline.commands },
                .summary = .{},
                .mutants = &.{},
            },
        };
    }

    // Generate candidates over the discovered files, then filter.
    const candidates = try generateCandidates(arena, cfg, files, options);

    // Run each mutant and build report entries.
    var entries: std.ArrayList(report.Mutant) = .empty;
    for (candidates) |candidate| {
        const source = sourceFor(files, candidate.file) orelse continue;
        const result = mutant_executor.run(candidate, source, cfg.test_commands, mode);
        try entries.append(arena, try buildEntry(arena, candidate, source, cfg, result, mode));
    }
    const mutants = try entries.toOwnedSlice(arena);
    report.sortAndAssignDisplayIds(mutants);
    const summary = report.summarize(mutants);

    var exit_code: u8 = 0;
    if (options.fail_on_survivors and summary.survived > 0) exit_code = 1;

    return .{
        .exit_code = exit_code,
        .report = .{
            .run = baseRun(obs, .completed),
            .baseline = .{ .status = .passed, .commands = baseline.commands },
            .summary = summary,
            .mutants = mutants,
        },
    };
}

fn baseRun(obs: Observation, status: report.RunStatus) report.Run {
    return .{
        .id = obs.run_id,
        .status = status,
        .@"error" = null,
        .zentinel_version = obs.zentinel_version,
        .zig_version = obs.zig_version,
        .command = "zentinel run",
        .config_hash = obs.config_hash,
        .project_root = obs.project_root,
        .started_at = obs.started_at,
        .duration_ms = obs.duration_ms,
    };
}

fn sourceFor(files: []const FileSource, path: []const u8) ?[]const u8 {
    for (files) |f| {
        if (std.mem.eql(u8, f.path, path)) return f.source;
    }
    return null;
}

fn enabled(cfg: config.Config, operator: []const u8) bool {
    for (cfg.mutators_enabled) |op| {
        if (std.mem.eql(u8, op, operator)) return true;
    }
    return false;
}

/// Recognize Phase 1 AST candidates over every file, then keep only those whose
/// operator is enabled in config and that match the optional CLI filters.
fn generateCandidates(arena: std.mem.Allocator, cfg: config.Config, files: []const FileSource, options: Options) RunError![]mutant.Mutant {
    var collector = ast_backend.Collector.init(arena);
    for (files) |f| {
        var parsed = try ast_backend.parse(arena, f.path, f.source);
        defer parsed.deinit();
        if (!parsed.ok()) continue; // skip files that do not parse
        const test_ranges = try ast_backend.testDeclRanges(parsed, arena);
        try arithmetic.collect(&collector, parsed, f.path, test_ranges);
        try comparison.collect(&collector, parsed, f.path, test_ranges);
        try logical.collect(&collector, parsed, f.path, test_ranges);
        try boolean.collect(&collector, parsed, f.path, test_ranges);
    }
    const all = try collector.finish();

    var kept: std.ArrayList(mutant.Mutant) = .empty;
    for (all) |c| {
        if (!enabled(cfg, c.operator)) continue;
        if (options.operator_filter) |op| {
            if (!std.mem.eql(u8, c.operator, op)) continue;
        }
        if (options.mutant_filter) |id| {
            if (!std.mem.eql(u8, c.id, id)) continue;
        }
        try kept.append(arena, c);
    }
    return kept.toOwnedSlice(arena);
}

fn buildEntry(
    arena: std.mem.Allocator,
    candidate: mutant.Mutant,
    source: []const u8,
    cfg: config.Config,
    result: mutant_runner.MutationResult,
    mode: report.Mode,
) std.mem.Allocator.Error!report.Mutant {
    var duration: u64 = 0;
    for (result.commands) |c| duration += c.duration_ms;

    return .{
        .id = candidate.id,
        .display_id = 1, // reassigned after sorting
        .backend = candidate.backend,
        .backend_stability = candidate.backend_stability,
        .operator = candidate.operator,
        .operator_stability = candidate.operator_stability,
        .file = candidate.file,
        .span = candidate.span,
        .original = candidate.original,
        .replacement = candidate.replacement,
        .diff = try computeDiff(arena, source, candidate),
        .expected_compile = candidate.expected_compile,
        .result = .{
            .status = result.status,
            .mode = mode,
            .commands = result.commands,
            .phase = .mutant,
            .duration_ms = duration,
            .evidence = result.evidence,
            .skip_reason = result.skip_reason,
        },
        .test_selection = .{
            .strategy = .all,
            .selected = &.{},
            .commands = cfg.test_commands,
            .preflight_commands = &.{},
            .fallback_used = false,
        },
        .advisory = .{ .equivalent_risks = candidate.equivalent_risks, .ai = null },
    };
}

/// Line-level diff for one mutant: the original line and the patched line.
fn computeDiff(arena: std.mem.Allocator, source: []const u8, candidate: mutant.Mutant) std.mem.Allocator.Error![]const []const u8 {
    const start: usize = candidate.span.byte_start;
    const end: usize = candidate.span.byte_end;
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..start], '\n')) |i| i + 1 else 0;
    const line_end = if (std.mem.indexOfScalarPos(u8, source, end, '\n')) |i| i else source.len;
    const original_line = source[line_start..line_end];

    var patched: std.ArrayList(u8) = .empty;
    try patched.appendSlice(arena, source[line_start..start]);
    try patched.appendSlice(arena, candidate.replacement);
    try patched.appendSlice(arena, source[end..line_end]);

    const minus = try std.fmt.allocPrint(arena, "- {s}", .{original_line});
    const plus = try std.fmt.allocPrint(arena, "+ {s}", .{patched.items});
    return try arena.dupe([]const u8, &.{ minus, plus });
}
