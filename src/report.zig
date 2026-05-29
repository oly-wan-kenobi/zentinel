// Layer: deterministic_core
//
// Typed zentinel report model and deterministic JSON serialization
// (docs/REPORT_FORMAT.md, schemas/report.v1.schema.json). Pure: no command
// execution or mutant generation. Struct field order is the canonical JSON key
// order. JSON Schema validation checks shape; `validate` is the second oracle
// that checks derived invariants JSON Schema cannot fully prove (summary
// derivation, display-id ordering, cross-field run/baseline rules).
const std = @import("std");
const mutant = @import("mutant.zig");

pub const schema_version = "zentinel.report.v1";

pub const RunStatus = enum { completed, baseline_failed, internal_error };
pub const BaselineStatus = enum { passed, failed, not_run };
pub const Phase = enum { baseline, mutant, selection_preflight };
pub const CommandStatus = enum { passed, failed, timeout, compiler_crash, skipped };
pub const FailureKind = enum { none, compile_error, test_failure, compiler_crash, timeout, skipped };
pub const ResultStatus = enum { killed, survived, compile_error, compiler_crash, timeout, skipped, invalid };
// Backend/stability/compile-expectation enums are owned by the shared mutant
// model so the report consumes one source of truth (task 007).
pub const BackendStability = mutant.BackendStability;
pub const OperatorStability = mutant.OperatorStability;
pub const Backend = mutant.Backend;
pub const Mode = enum { Debug, ReleaseSafe, ReleaseFast, ReleaseSmall };
pub const ExpectedCompile = mutant.ExpectedCompile;
pub const EnvironmentPolicy = enum { minimal };
pub const CacheMode = enum { disabled, metadata_only, read_write };
pub const ErrorPhase = enum { internal, report, backend, mutator, sandbox, runner, cache, task };
pub const Strategy = enum { all, same_file, same_file_then_package, impact_graph };

pub const CommandEvidence = struct {
    original: []const u8,
    argv: []const []const u8,
    cwd: []const u8,
    environment_policy: EnvironmentPolicy = .minimal,
    shell: bool = false,
};

pub const Evidence = struct {
    stdout_excerpt: []const u8 = "",
    stderr_excerpt: []const u8 = "",
    failure_summary: []const u8 = "",
};

pub const CommandResult = struct {
    command: CommandEvidence,
    phase: Phase,
    status: CommandStatus,
    exit_code: ?i64,
    timed_out: bool,
    failure_kind: FailureKind,
    duration_ms: u64,
    evidence: Evidence,
    skip_reason: ?[]const u8,
};

pub const RunError = struct {
    code: []const u8,
    message: []const u8,
    phase: ErrorPhase,
    /// Optional bounded detail; always serialized (empty by default) to keep the
    /// closed object shape stable.
    details: []const []const u8 = &.{},
};

pub const Run = struct {
    id: []const u8,
    status: RunStatus,
    @"error": ?RunError,
    zentinel_version: []const u8,
    zig_version: []const u8,
    command: []const u8,
    config_hash: []const u8,
    project_root: []const u8,
    started_at: []const u8,
    duration_ms: u64,
};

pub const Baseline = struct {
    status: BaselineStatus,
    commands: []const CommandResult,
};

pub const CacheDiagnostics = struct {
    enabled: bool = false,
    mode: CacheMode = .disabled,
    hits: u64 = 0,
    misses: u64 = 0,
};

pub const Diagnostics = struct {
    cache: CacheDiagnostics = .{},
};

pub const Summary = struct {
    total: u64 = 0,
    killed: u64 = 0,
    survived: u64 = 0,
    compile_error: u64 = 0,
    compiler_crash: u64 = 0,
    timeout: u64 = 0,
    skipped: u64 = 0,
    invalid: u64 = 0,
};

/// Source span, owned by the shared mutant model (task 007).
pub const Span = mutant.Span;

pub const SelectedTest = struct {
    file: []const u8,
    name: []const u8,
    line: u32,
};

pub const Result = struct {
    status: ResultStatus,
    mode: Mode,
    commands: []const CommandResult,
    phase: Phase = .mutant,
    duration_ms: u64,
    evidence: Evidence,
    skip_reason: ?[]const u8,
};

pub const TestSelection = struct {
    strategy: Strategy,
    selected: []const SelectedTest,
    commands: []const []const u8,
    preflight_commands: []const CommandResult,
    fallback_used: bool,
};

/// Advisory AI placeholder. Deterministic core never populates it; it exists so
/// `advisory.ai` keeps a stable optional-object shape distinct from classification.
pub const Ai = struct {};

pub const Advisory = struct {
    equivalent_risks: []const []const u8 = &.{},
    ai: ?Ai = null,
};

pub const Mutant = struct {
    id: []const u8,
    display_id: u32,
    backend: Backend,
    backend_stability: BackendStability,
    operator: []const u8,
    operator_stability: OperatorStability,
    file: []const u8,
    span: Span,
    original: []const u8,
    replacement: []const u8,
    diff: []const []const u8,
    expected_compile: ExpectedCompile,
    result: Result,
    test_selection: TestSelection,
    advisory: Advisory,
};

pub const Report = struct {
    schema_version: []const u8 = schema_version,
    run: Run,
    baseline: Baseline,
    diagnostics: Diagnostics = .{},
    summary: Summary,
    mutants: []const Mutant,
};

// --- Serialization ---------------------------------------------------------

/// Serialize a report as deterministic, pretty-printed canonical JSON.
pub fn toJson(arena: std.mem.Allocator, report: Report) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, report, .{ .whitespace = .indent_2 });
}

/// Stream a report as canonical JSON to a writer.
pub fn writeJson(report: Report, writer: *std.Io.Writer) std.json.Stringify.Error!void {
    return std.json.Stringify.value(report, .{ .whitespace = .indent_2 }, writer);
}

// --- Summary + ordering ----------------------------------------------------

/// Derive summary counts only from the mutant entries (I-? report invariant).
pub fn summarize(mutants: []const Mutant) Summary {
    var s = Summary{ .total = mutants.len };
    for (mutants) |m| switch (m.result.status) {
        .killed => s.killed += 1,
        .survived => s.survived += 1,
        .compile_error => s.compile_error += 1,
        .compiler_crash => s.compiler_crash += 1,
        .timeout => s.timeout += 1,
        .skipped => s.skipped += 1,
        .invalid => s.invalid += 1,
    };
    return s;
}

/// Canonical candidate ordering: file, byte start, byte end, operator,
/// replacement, backend (docs/REPORT_FORMAT.md Ordering).
fn lessMutant(_: void, a: Mutant, b: Mutant) bool {
    switch (std.mem.order(u8, a.file, b.file)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    if (a.span.byte_start != b.span.byte_start) return a.span.byte_start < b.span.byte_start;
    if (a.span.byte_end != b.span.byte_end) return a.span.byte_end < b.span.byte_end;
    switch (std.mem.order(u8, a.operator, b.operator)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.mem.order(u8, a.replacement, b.replacement)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    return @intFromEnum(a.backend) < @intFromEnum(b.backend);
}

/// Sort mutants into canonical order and assign 1-based report-local display ids.
pub fn sortAndAssignDisplayIds(mutants: []Mutant) void {
    std.mem.sort(Mutant, mutants, {}, lessMutant);
    for (mutants, 0..) |*m, i| m.display_id = @intCast(i + 1);
}

// --- Semantic validation ---------------------------------------------------

pub const Violation = enum {
    ok,
    summary_total_mismatch,
    summary_count_mismatch,
    display_id_ordering,
    completed_requires_baseline_passed,
    baseline_failed_requires_failed_baseline,
    baseline_failed_requires_empty_mutants,
    baseline_failed_requires_zero_counts,
    internal_error_requires_run_error,
    run_error_must_be_null,
    baseline_not_run_with_mutants,
    baseline_empty_commands,
    baseline_command_skipped,
    baseline_timeout_requires_baseline_failed,
    empty_argv0,
    mutant_command_phase,
    skip_reason_required,
    skip_reason_must_be_null,
    invalid_failure_summary_prefix,
};

fn allZero(s: Summary) bool {
    return s.total == 0 and s.killed == 0 and s.survived == 0 and s.compile_error == 0 and
        s.compiler_crash == 0 and s.timeout == 0 and s.skipped == 0 and s.invalid == 0;
}

fn evidenceArgvOk(cmds: []const CommandResult) bool {
    for (cmds) |c| {
        if (c.command.argv.len == 0 or c.command.argv[0].len == 0) return false;
    }
    return true;
}

/// Deterministic semantic validator: the second report oracle beyond JSON
/// Schema. Returns `.ok` or the first violated invariant in a fixed order.
pub fn validate(report: Report) Violation {
    // Derived summary invariants.
    if (report.summary.total != report.mutants.len) return .summary_total_mismatch;
    const derived = summarize(report.mutants);
    if (!std.meta.eql(report.summary, derived)) return .summary_count_mismatch;

    // Report-local display ids must follow canonical ordering 1..N.
    for (report.mutants, 0..) |m, i| {
        if (m.display_id != @as(u32, @intCast(i + 1))) return .display_id_ordering;
        if (i > 0 and lessMutant({}, report.mutants[i], report.mutants[i - 1])) return .display_id_ordering;
    }

    // Run-level status cross-field rules.
    switch (report.run.status) {
        .completed => {
            if (report.baseline.status != .passed) return .completed_requires_baseline_passed;
            if (report.run.@"error" != null) return .run_error_must_be_null;
        },
        .baseline_failed => {
            if (report.baseline.status != .failed) return .baseline_failed_requires_failed_baseline;
            if (report.mutants.len != 0) return .baseline_failed_requires_empty_mutants;
            if (!allZero(report.summary)) return .baseline_failed_requires_zero_counts;
            if (report.run.@"error" != null) return .run_error_must_be_null;
        },
        .internal_error => {
            if (report.run.@"error" == null) return .internal_error_requires_run_error;
        },
    }

    // Baseline shape.
    if (report.baseline.status == .not_run) {
        if (report.mutants.len != 0) return .baseline_not_run_with_mutants;
    } else if (report.baseline.commands.len == 0) {
        return .baseline_empty_commands;
    }
    for (report.baseline.commands) |c| {
        if (c.status == .skipped) return .baseline_command_skipped;
        if (c.status == .timeout and report.run.status != .baseline_failed) return .baseline_timeout_requires_baseline_failed;
    }
    if (!evidenceArgvOk(report.baseline.commands)) return .empty_argv0;

    // Mutant result invariants.
    for (report.mutants) |m| {
        if (!evidenceArgvOk(m.result.commands)) return .empty_argv0;
        if (!evidenceArgvOk(m.test_selection.preflight_commands)) return .empty_argv0;
        for (m.result.commands) |c| {
            if (c.phase != .mutant) return .mutant_command_phase;
        }
        if (m.result.status == .skipped) {
            const reason = m.result.skip_reason orelse return .skip_reason_required;
            if (reason.len == 0) return .skip_reason_required;
        } else if (m.result.skip_reason != null) {
            return .skip_reason_must_be_null;
        }
        if (m.result.status == .invalid and !invalidSummaryOk(m.result.evidence.failure_summary)) {
            return .invalid_failure_summary_prefix;
        }
    }

    return .ok;
}

fn invalidSummaryOk(failure_summary: []const u8) bool {
    return std.mem.startsWith(u8, failure_summary, "patch:") or
        std.mem.startsWith(u8, failure_summary, "sandbox:") or
        std.mem.startsWith(u8, failure_summary, "backend:");
}

// --- Repeated-run normalization --------------------------------------------

/// Normalize the canonical JSON for repeated-run comparison by replacing only
/// the documented observation metadata: `run.id`, `run.started_at`, and every
/// `duration_ms` value (docs/REPORT_FORMAT.md Repeated-Run Comparison). No other
/// field may differ between deterministic runs.
pub fn normalizeForComparison(arena: std.mem.Allocator, json: []const u8) std.mem.Allocator.Error![]const u8 {
    const durations = try normalizeDurations(arena, json);
    const ids = try replaceQuotedTokenWithPrefix(arena, durations, "run_", "<run-id>");
    return replaceKeyStringValue(arena, ids, "started_at", "<started-at>");
}

fn normalizeDurations(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    const key = "\"duration_ms\":";
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], key)) {
            try out.appendSlice(arena, key);
            i += key.len;
            while (i < text.len and text[i] == ' ') : (i += 1) try out.append(arena, ' ');
            var had_digit = false;
            while (i < text.len and text[i] >= '0' and text[i] <= '9') : (i += 1) had_digit = true;
            if (had_digit) try out.appendSlice(arena, "<duration>");
        } else {
            try out.append(arena, text[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(arena);
}

/// Replace a JSON string token whose content starts with `prefix` (e.g. the
/// `run_...` run id) with `"<replacement>"`. Targets the unique run-id value.
fn replaceQuotedTokenWithPrefix(arena: std.mem.Allocator, text: []const u8, prefix: []const u8, replacement: []const u8) std.mem.Allocator.Error![]const u8 {
    const needle = try std.fmt.allocPrint(arena, "\"{s}", .{prefix});
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], needle)) {
            try out.append(arena, '"');
            try out.appendSlice(arena, replacement);
            try out.append(arena, '"');
            i += 1; // skip opening quote
            while (i < text.len and text[i] != '"') i += 1; // skip token body
            if (i < text.len) i += 1; // skip closing quote
        } else {
            try out.append(arena, text[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(arena);
}

/// Replace the quoted string value following `"key":` with `"<placeholder>"`.
fn replaceKeyStringValue(arena: std.mem.Allocator, text: []const u8, key: []const u8, placeholder: []const u8) std.mem.Allocator.Error![]const u8 {
    const needle = try std.fmt.allocPrint(arena, "\"{s}\":", .{key});
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], needle)) {
            try out.appendSlice(arena, needle);
            i += needle.len;
            while (i < text.len and text[i] == ' ') : (i += 1) try out.append(arena, ' ');
            if (i < text.len and text[i] == '"') {
                try out.append(arena, '"');
                try out.appendSlice(arena, placeholder);
                try out.append(arena, '"');
                i += 1;
                while (i < text.len and text[i] != '"') i += 1;
                if (i < text.len) i += 1;
            }
        } else {
            try out.append(arena, text[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(arena);
}
