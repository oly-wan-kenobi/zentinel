// Layer: deterministic_core
//
// Typed doctest report model and deterministic JSON serialization
// (docs/DOCTEST_SPEC.md "Doctest Reports", schemas/doctest.report.v1.schema.json).
// Pure: no execution. Struct field order is the canonical JSON key order.
// `validate` is the second oracle for derived invariants (summary derivation,
// case ordering, run/error cross-field rules) that JSON Schema cannot fully
// prove. Mutation-aware reports are a later task; this is the normal report.
const std = @import("std");
const case_mod = @import("case.zig");
const runner = @import("runner.zig");
const matcher = @import("matcher.zig");

pub const schema_version = "zentinel.doctest.report.v1";

pub const RunStatus = enum { completed, failed, internal_error };
pub const ErrorPhase = enum { internal, parser, extractor, runner, snapshot, report };
pub const CaseKind = case_mod.CaseKind;
pub const Status = runner.Status;
pub const MatchMode = matcher.Mode;
pub const ActualRef = enum { stdout, stderr, diagnostic, json, report };
pub const EnvironmentPolicy = enum { minimal };

pub const RunError = struct {
    code: []const u8,
    message: []const u8,
    phase: ErrorPhase,
    details: []const []const u8 = &.{},
};

pub const Run = struct {
    id: []const u8,
    status: RunStatus,
    @"error": ?RunError,
    zentinel_version: []const u8,
    zig_version: []const u8,
    command: []const u8,
    project_root: []const u8,
    started_at: []const u8,
    duration_ms: u64,
};

pub const Summary = struct {
    total: u64 = 0,
    passed: u64 = 0,
    failed: u64 = 0,
    compile_error: u64 = 0,
    expected_compile_error: u64 = 0,
    timeout: u64 = 0,
    skipped: u64 = 0,
    invalid: u64 = 0,
};

pub const Expectation = struct {
    mode: MatchMode,
    block_ref: []const u8,
};

pub const Command = struct {
    original: []const u8,
    argv: []const []const u8,
    cwd: []const u8,
    environment_policy: EnvironmentPolicy = .minimal,
    shell: bool = false,
};

pub const Snapshot = struct {
    expected_excerpt: []const u8,
    actual_excerpt: []const u8,
    normalized_expected_excerpt: []const u8,
    normalized_actual_excerpt: []const u8,
    match_mode: MatchMode,
    expected_block_ref: ?[]const u8,
    actual_ref: ActualRef,
    matched: bool,
};

pub const Result = struct {
    exit_code: ?i64,
    timed_out: bool,
    duration_ms: u64,
    stdout_excerpt: []const u8,
    stderr_excerpt: []const u8,
    normalized_stdout_excerpt: []const u8,
    normalized_stderr_excerpt: []const u8,
    snapshot: ?Snapshot,
    failure_summary: []const u8,
};

pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
};

/// Advisory AI placeholder; deterministic core never populates it.
pub const Ai = struct {};

pub const Advisory = struct {
    ai: ?Ai = null,
};

pub const Case = struct {
    id: []const u8,
    file: []const u8,
    line_start: u32,
    line_end: u32,
    source_ref: []const u8,
    block_refs: []const []const u8,
    kind: CaseKind,
    status: Status,
    expectation: ?Expectation,
    command: ?Command,
    result: ?Result,
    diagnostics: []const Diagnostic,
    advisory: Advisory = .{},
};

pub const Report = struct {
    schema_version: []const u8 = schema_version,
    run: Run,
    summary: Summary,
    cases: []const Case,
};

// --- Serialization ---------------------------------------------------------

pub fn toJson(arena: std.mem.Allocator, report: Report) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, report, .{ .whitespace = .indent_2 });
}

// --- Summary + ordering ----------------------------------------------------

pub fn summarize(cases: []const Case) Summary {
    var s = Summary{ .total = cases.len };
    for (cases) |c| switch (c.status) {
        .passed => s.passed += 1,
        .failed => s.failed += 1,
        .compile_error => s.compile_error += 1,
        .expected_compile_error => s.expected_compile_error += 1,
        .timeout => s.timeout += 1,
        .skipped => s.skipped += 1,
        .invalid => s.invalid += 1,
    };
    return s;
}

/// Cases sorted by project file path, anchor line, then durable case id.
pub fn lessCase(_: void, a: Case, b: Case) bool {
    switch (std.mem.order(u8, a.file, b.file)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    if (a.line_start != b.line_start) return a.line_start < b.line_start;
    return std.mem.order(u8, a.id, b.id) == .lt;
}

pub fn sortCases(cases: []Case) void {
    std.mem.sort(Case, cases, {}, lessCase);
}

/// 1 if any case status is not passed/skipped/expected_compile_error, else 0
/// (docs/DOCTEST_SPEC.md exit semantics).
pub fn exitCode(report: Report) u8 {
    if (report.run.status == .internal_error) return 4;
    for (report.cases) |c| switch (c.status) {
        .passed, .skipped, .expected_compile_error => {},
        else => return 1,
    };
    return 0;
}

// --- Semantic validation ---------------------------------------------------

pub const Violation = enum {
    ok,
    summary_total_mismatch,
    summary_count_mismatch,
    case_ordering,
    completed_requires_no_error,
    failed_requires_no_error,
    internal_error_requires_error,
    snapshot_missing_block_ref,
};

pub fn validate(report: Report) Violation {
    if (report.summary.total != report.cases.len) return .summary_total_mismatch;
    const derived = summarize(report.cases);
    if (!std.meta.eql(report.summary, derived)) return .summary_count_mismatch;

    for (report.cases, 0..) |c, i| {
        if (i > 0 and lessCase({}, report.cases[i], report.cases[i - 1])) return .case_ordering;
        if (c.result) |r| {
            if (r.snapshot) |snap| {
                if (snap.expected_block_ref) |ref| {
                    if (ref.len == 0) return .snapshot_missing_block_ref;
                }
            }
        }
    }

    switch (report.run.status) {
        .completed => if (report.run.@"error" != null) return .completed_requires_no_error,
        .failed => if (report.run.@"error" != null) return .failed_requires_no_error,
        .internal_error => if (report.run.@"error" == null) return .internal_error_requires_error,
    }
    return .ok;
}

// --- Repeated-run normalization --------------------------------------------

/// Normalize canonical JSON for repeated-run comparison: only `run.id`,
/// `run.started_at`, and every `duration_ms` value may differ between runs.
pub fn normalizeForComparison(arena: std.mem.Allocator, json: []const u8) std.mem.Allocator.Error![]const u8 {
    const durations = try normalizeDurations(arena, json);
    const ids = try replaceKeyStringValue(arena, durations, "id", "<run-id>", "doctest_run_");
    return replaceKeyStringValue(arena, ids, "started_at", "<started-at>", "");
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

/// Replace the quoted string value after `"key":` with `"<placeholder>"`. When
/// `value_prefix` is non-empty, only replace when the value starts with it (so a
/// generic key like `id` only matches the run id, not case ids).
fn replaceKeyStringValue(arena: std.mem.Allocator, text: []const u8, key: []const u8, placeholder: []const u8, value_prefix: []const u8) std.mem.Allocator.Error![]const u8 {
    const needle = try std.fmt.allocPrint(arena, "\"{s}\":", .{key});
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], needle)) {
            var j = i + needle.len;
            while (j < text.len and text[j] == ' ') j += 1;
            if (j < text.len and text[j] == '"') {
                const val_start = j + 1;
                var k = val_start;
                while (k < text.len and text[k] != '"') k += 1;
                const value = text[val_start..k];
                if (value_prefix.len == 0 or std.mem.startsWith(u8, value, value_prefix)) {
                    try out.appendSlice(arena, needle);
                    try out.appendSlice(arena, text[i + needle.len .. j]);
                    try out.append(arena, '"');
                    try out.appendSlice(arena, placeholder);
                    try out.append(arena, '"');
                    i = if (k < text.len) k + 1 else k;
                    continue;
                }
            }
        }
        try out.append(arena, text[i]);
        i += 1;
    }
    return out.toOwnedSlice(arena);
}
