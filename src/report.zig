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
// model so the report consumes one source of truth.
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

/// Source span, owned by the shared mutant model.
pub const Span = mutant.Span;

pub const SelectedTest = struct {
    file: []const u8,
    name: []const u8,
    line: u32,
};

/// One mode's outcome for a mutant in the safety/optimization mode matrix.
/// An additive `zentinel.report.v1` extension carried only inside the
/// optional `Result.mode_matrix`; it never replaces `result.mode`.
pub const ModeResult = struct {
    mode: Mode,
    status: ResultStatus,
};

pub const Result = struct {
    status: ResultStatus,
    mode: Mode,
    commands: []const CommandResult,
    phase: Phase = .mutant,
    duration_ms: u64,
    evidence: Evidence,
    skip_reason: ?[]const u8,
    /// Optional safety/optimization mode matrix. Null (and omitted
    /// from JSON) for single-mode runs, so existing single-mode reports are
    /// byte-identical; populated only when more than one mode is run.
    mode_matrix: ?[]const ModeResult = null,

    /// Custom serialization so the additive `mode_matrix` is omitted entirely when
    /// null (preserving single-mode report bytes) while every other field keeps
    /// the default reflection-based encoding and order.
    pub fn jsonStringify(self: Result, jws: *std.json.Stringify) std.json.Stringify.Error!void {
        try jws.beginObject();
        try jws.objectField("status");
        try jws.write(self.status);
        try jws.objectField("mode");
        try jws.write(self.mode);
        try jws.objectField("commands");
        try jws.write(self.commands);
        try jws.objectField("phase");
        try jws.write(self.phase);
        try jws.objectField("duration_ms");
        try jws.write(self.duration_ms);
        try jws.objectField("evidence");
        try jws.write(self.evidence);
        try jws.objectField("skip_reason");
        try jws.write(self.skip_reason);
        if (self.mode_matrix) |mm| {
            try jws.objectField("mode_matrix");
            try jws.write(mm);
        }
        try jws.endObject();
    }
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

/// Serialize a report as deterministic, pretty-printed canonical JSON. This is
/// the single report serializer: the CLI writes the returned buffer with
/// `writeFile` (atomic, symlink-safe), so there is no streaming variant to drift
/// out of sync with it.
pub fn toJson(arena: std.mem.Allocator, report: Report) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, report, .{ .whitespace = .indent_2 });
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
    run_error_code_blank,
    run_error_message_blank,
    run_error_must_be_null,
    baseline_not_run_with_mutants,
    baseline_empty_commands,
    baseline_command_skipped,
    baseline_command_phase,
    baseline_timeout_requires_baseline_failed,
    empty_argv0,
    mutant_command_phase,
    preflight_command_phase,
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

fn commandSkipReasonViolation(cmds: []const CommandResult) ?Violation {
    for (cmds) |c| {
        if (c.status == .skipped) {
            const reason = c.skip_reason orelse return .skip_reason_required;
            if (reason.len == 0) return .skip_reason_required;
        } else if (c.skip_reason != null) {
            return .skip_reason_must_be_null;
        }
    }
    return null;
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
            // run.error must be present and its stable code/message non-blank. The
            // ZNTL_ code shape (^ZNTL_[A-Z0-9_]+$) is proven by the JSON Schema; the
            // second oracle only guarantees the fields are not empty, mirroring the
            // mutant_command_phase invariant the schema cannot fully express.
            const e = report.run.@"error" orelse return .internal_error_requires_run_error;
            if (e.code.len == 0) return .run_error_code_blank;
            if (e.message.len == 0) return .run_error_message_blank;
        },
    }

    // Baseline shape.
    if (report.baseline.status == .not_run) {
        if (report.mutants.len != 0) return .baseline_not_run_with_mutants;
    } else if (report.baseline.commands.len == 0) {
        return .baseline_empty_commands;
    }
    for (report.baseline.commands) |c| {
        if (c.phase != .baseline) return .baseline_command_phase;
        if (c.status == .skipped) return .baseline_command_skipped;
        if (c.status == .timeout and report.run.status != .baseline_failed) return .baseline_timeout_requires_baseline_failed;
    }
    if (!evidenceArgvOk(report.baseline.commands)) return .empty_argv0;
    if (commandSkipReasonViolation(report.baseline.commands)) |v| return v;

    // Mutant result invariants.
    for (report.mutants) |m| {
        if (!evidenceArgvOk(m.result.commands)) return .empty_argv0;
        if (!evidenceArgvOk(m.test_selection.preflight_commands)) return .empty_argv0;
        for (m.result.commands) |c| {
            if (c.phase != .mutant) return .mutant_command_phase;
        }
        for (m.test_selection.preflight_commands) |c| {
            if (c.phase != .selection_preflight) return .preflight_command_phase;
        }
        if (commandSkipReasonViolation(m.result.commands)) |v| return v;
        if (commandSkipReasonViolation(m.test_selection.preflight_commands)) |v| return v;
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

// --- Observation timestamp -------------------------------------------------

/// Format epoch-milliseconds as a UTC ISO-8601 second-precision timestamp
/// (`YYYY-MM-DDThh:mm:ssZ`), the canonical form of `run.started_at`. Negative
/// inputs clamp to the epoch and sub-second milliseconds are truncated. Pure and
/// deterministic: the wall-clock read stays in the CLI, so the run observation and
/// the doctest run share this one formatter instead of duplicating it.
pub fn isoTimestamp(gpa: std.mem.Allocator, ms: i64) std.mem.Allocator.Error![]const u8 {
    const secs: u64 = @intCast(@max(0, @divTrunc(ms, 1000)));
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const day = es.getDaySeconds();
    return std.fmt.allocPrint(gpa, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year, md.month.numeric(), md.day_index + 1, day.getHoursIntoDay(), day.getMinutesIntoHour(), day.getSecondsIntoMinute(),
    });
}

// --- Repeated-run normalization --------------------------------------------

/// Normalize the canonical JSON for repeated-run comparison by replacing only
/// the documented observation metadata: `run.id`, `run.started_at`, and every
/// `duration_ms` value (docs/REPORT_FORMAT.md Repeated-Run Comparison). No other
/// field may differ between deterministic runs.
pub fn normalizeForComparison(arena: std.mem.Allocator, json: []const u8) std.mem.Allocator.Error![]const u8 {
    const durations = try normalizeDurations(arena, json);
    // Replace the run id by its EXACT value, extracted from the `"id"` field,
    // then substituted wherever it appears (run.id plus any workspace path that
    // embeds it). Scanning for the literal `"run_` prefix -- as the previous
    // implementation did -- over-matched unrelated quoted strings that happen to
    // start with `run_` (an argv entry like `"run_specs"`, a file path like
    // `"run_utils/x.zig"`, a test name), collapsing a real value to the
    // placeholder and corrupting the comparison.
    const run_id = extractStringKeyValue(json, "id") orelse "";
    const ids = if (run_id.len > 0)
        try replaceAll(arena, durations, run_id, "<run-id>")
    else
        durations;
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

/// Extract the string value of the first `"key":` field in `text`, tolerating
/// optional whitespace after the colon. Returns null if the key is absent or its
/// value is not a string.
fn extractStringKeyValue(text: []const u8, key: []const u8) ?[]const u8 {
    var stack: [16]u8 = undefined;
    const needle = std.fmt.bufPrint(&stack, "\"{s}\":", .{key}) catch return null;
    var i: usize = 0;
    while (i + needle.len <= text.len) : (i += 1) {
        if (!std.mem.startsWith(u8, text[i..], needle)) continue;
        var j = i + needle.len;
        while (j < text.len and text[j] == ' ') j += 1;
        if (j >= text.len or text[j] != '"') continue;
        const val_start = j + 1;
        var k = val_start;
        while (k < text.len and text[k] != '"') k += 1;
        if (k >= text.len) continue;
        return text[val_start..k];
    }
    return null;
}

/// Replace every occurrence of the literal `needle` with `replacement`.
fn replaceAll(arena: std.mem.Allocator, text: []const u8, needle: []const u8, replacement: []const u8) std.mem.Allocator.Error![]const u8 {
    if (needle.len == 0) return arena.dupe(u8, text);
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (i + needle.len <= text.len and std.mem.eql(u8, text[i .. i + needle.len], needle)) {
            try out.appendSlice(arena, replacement);
            i += needle.len;
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

/// Normalize a captured command-output excerpt so two real runs over the same
/// project produce identical excerpt bytes (docs/REPORT_FORMAT.md, Repeated-Run
/// Comparison). Test panics and assertion stack traces embed ASLR pointer
/// addresses (`0x<hex>`, which differ on every run) and absolute machine paths
/// (which differ across machines); both are replaced with the stable placeholders
/// `0x<addr>` and `<path>` so a killed mutant's stderr can no longer make the
/// report non-deterministic. An absolute path is recognized whether it starts the
/// line, follows whitespace/quote/bracket, or is glued to a `=`/`:`/`>`/`,` or a
/// `scheme://` prefix. Surrounding prose is preserved (excerpts are
/// normalized, never dropped). Returns an arena-owned copy; the input is unchanged.
pub fn normalizeExcerpt(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        // Hex pointer address: `0x`/`0X` followed by one or more hex digits.
        if (text[i] == '0' and i + 2 < text.len and (text[i + 1] == 'x' or text[i + 1] == 'X') and isHexDigit(text[i + 2])) {
            try out.appendSlice(arena, "0x<addr>");
            i += 2;
            while (i < text.len and isHexDigit(text[i])) i += 1;
            continue;
        }
        // Absolute path token: Unix `/abs/path` entries and Windows `C:\path`
        // entries are replaced even when quoted paths contain spaces. This keeps
        // repeated-run comparison stable across developer machines.
        // A `/` begins an absolute path at a token boundary: start of text, after
        // a non-path byte, OR after a `:`. Build/test output routinely glues a path
        // to a preceding `=`, `:`, `>` or `,` (`key=/abs`, `note:/abs`, redirection
        // `2>/abs`) or embeds it in a `scheme://` URI; the old positive-set boundary
        // (whitespace/quote/bracket only) left those verbatim, leaking the absolute
        // developer path into the committed report and breaking cross-machine
        // determinism. This mirrors redaction.normalizeAbsolutePaths so
        // the two normalizers stay consistent.
        const prev_is_colon = i > 0 and text[i - 1] == ':';
        const at_boundary = i == 0 or !isExcerptPathByte(text[i - 1]) or prev_is_colon;
        // A `//`-led run is a Zig comment marker (`//`, `///`, `//!`), not an
        // absolute path; excluding it keeps source-line comments in committed
        // excerpts intact instead of collapsing them to `<path>` -- EXCEPT when
        // the `//` is glued to a preceding `:` as a `scheme://` separator, where it
        // introduces a URI path to redact.
        const comment_marker = i + 1 < text.len and text[i + 1] == '/' and !prev_is_colon;
        if (text[i] == '/' and at_boundary and !comment_marker) {
            var end = i + 1;
            var inner_slashes: usize = 0;
            const quote: ?u8 = if (i > 0 and isExcerptQuote(text[i - 1])) text[i - 1] else null;
            while (end < text.len) : (end += 1) {
                if (quote) |q| {
                    if (text[end] == q) break;
                } else if (isExcerptSpace(text[end])) {
                    if (!excerptSpaceContinuesPath(text, end)) break;
                }
                if (text[end] == '/') inner_slashes += 1;
            }
            end = trimPathPunctuation(text, i, end);
            if (inner_slashes >= 1) {
                try out.appendSlice(arena, "<path>");
                i = end;
                continue;
            }
        }
        if (isWindowsExcerptPathAt(text, i) and at_boundary) {
            var end = i + 3;
            const quote: ?u8 = if (i > 0 and isExcerptQuote(text[i - 1])) text[i - 1] else null;
            while (end < text.len) : (end += 1) {
                if (quote) |q| {
                    if (text[end] == q) break;
                } else if (isExcerptSpace(text[end])) {
                    if (!excerptSpaceContinuesPath(text, end)) break;
                } else if (text[end] == '"' or text[end] == '\'') break;
            }
            end = trimPathPunctuation(text, i, end);
            try out.appendSlice(arena, "<path>");
            i = end;
            continue;
        }
        try out.append(arena, text[i]);
        i += 1;
    }
    // Captured process output can contain invalid UTF-8 (truncated multibyte
    // sequences, or raw binary from a crash/panic). Left verbatim it would make
    // report.json non-UTF-8 (RFC 8259 8.1) and the JUnit <system-out>/<system-err>
    // text non-well-formed, so a strict CI parser rejects the whole suite. Replace
    // any invalid byte with U+FFFD so every report format stays valid.
    return sanitizeUtf8(arena, try out.toOwnedSlice(arena));
}

/// Replace every byte that is not part of a valid UTF-8 sequence with U+FFFD,
/// leaving valid text (the common case) untouched and unallocated.
fn sanitizeUtf8(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.unicode.utf8ValidateSlice(text)) return text;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
            try out.appendSlice(arena, "\u{FFFD}");
            i += 1;
            continue;
        };
        if (i + len > text.len or !std.unicode.utf8ValidateSlice(text[i..][0..len])) {
            try out.appendSlice(arena, "\u{FFFD}");
            i += 1;
            continue;
        }
        try out.appendSlice(arena, text[i..][0..len]);
        i += len;
    }
    return out.toOwnedSlice(arena);
}

fn isHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}
fn isExcerptSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}
fn isExcerptQuote(c: u8) bool {
    return c == '"' or c == '\'';
}
fn excerptSpaceContinuesPath(text: []const u8, space_index: usize) bool {
    if (text[space_index] == '\n' or text[space_index] == '\r') return false;
    var i = space_index;
    while (i < text.len and (text[i] == ' ' or text[i] == '\t')) i += 1;
    while (i < text.len) : (i += 1) {
        if (isExcerptSpace(text[i]) or isExcerptQuote(text[i])) return false;
        if (text[i] == '/' or text[i] == '\\') return true;
    }
    return false;
}
/// True for a byte that can appear inside an absolute-path token. A `/` is treated
/// as starting a path only when the preceding byte is NOT one of these (or is a
/// `:`), mirroring redaction.isPathByte so excerpt and AI-context path
/// normalization agree on token boundaries.
fn isExcerptPathByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '/' or c == '\\' or c == ':' or c == '.' or c == '_' or c == '-';
}
fn isWindowsExcerptPathAt(text: []const u8, i: usize) bool {
    return i + 2 < text.len and
        std.ascii.isAlphabetic(text[i]) and
        text[i + 1] == ':' and
        (text[i + 2] == '\\' or text[i + 2] == '/');
}
fn trimPathPunctuation(text: []const u8, start: usize, end_in: usize) usize {
    var end = end_in;
    while (end > start) {
        switch (text[end - 1]) {
            '.', ',', ';', ')' => end -= 1,
            else => break,
        }
    }
    return end;
}

// --- Performance equivalence + benchmark output ------------------------------

fn summaryEqual(a: Summary, b: Summary) bool {
    return a.total == b.total and a.killed == b.killed and a.survived == b.survived and
        a.compile_error == b.compile_error and a.compiler_crash == b.compiler_crash and
        a.timeout == b.timeout and a.skipped == b.skipped and a.invalid == b.invalid;
}

fn evidenceEqual(a: Evidence, b: Evidence) bool {
    return std.mem.eql(u8, a.stdout_excerpt, b.stdout_excerpt) and
        std.mem.eql(u8, a.stderr_excerpt, b.stderr_excerpt) and
        std.mem.eql(u8, a.failure_summary, b.failure_summary);
}

/// Two reports are equivalent for performance purposes when they agree on every
/// observable field -- run/baseline status, summary counts, and each mutant's
/// identity, ordering, status, selection, and command evidence -- ignoring only
/// volatile timing (`duration_ms`) and `diagnostics.cache`. This is the
/// determinism contract behind cached-versus-uncached, cold-versus-warm, and
/// serial-versus-parallel equivalence (docs/PERFORMANCE_STRATEGY.md).
pub fn equivalentIgnoringTiming(a: Report, b: Report) bool {
    if (a.run.status != b.run.status) return false;
    if (a.baseline.status != b.baseline.status) return false;
    if (!summaryEqual(a.summary, b.summary)) return false;
    if (a.baseline.commands.len != b.baseline.commands.len) return false;
    for (a.baseline.commands, b.baseline.commands) |ca, cb| {
        if (ca.status != cb.status) return false;
        if (ca.failure_kind != cb.failure_kind) return false;
        if (!evidenceEqual(ca.evidence, cb.evidence)) return false;
    }
    if (a.mutants.len != b.mutants.len) return false;
    for (a.mutants, b.mutants) |ma, mb| {
        if (!std.mem.eql(u8, ma.id, mb.id)) return false;
        if (ma.display_id != mb.display_id) return false;
        if (!std.mem.eql(u8, ma.operator, mb.operator)) return false;
        if (!std.mem.eql(u8, ma.file, mb.file)) return false;
        if (ma.result.status != mb.result.status) return false;
        if (ma.test_selection.strategy != mb.test_selection.strategy) return false;
        if (ma.test_selection.fallback_used != mb.test_selection.fallback_used) return false;
        if (ma.result.commands.len != mb.result.commands.len) return false;
        for (ma.result.commands, mb.result.commands) |ca, cb| {
            if (ca.status != cb.status) return false;
            if (ca.failure_kind != cb.failure_kind) return false;
            if (ca.exit_code != cb.exit_code) return false;
            if (!evidenceEqual(ca.evidence, cb.evidence)) return false;
            if ((ca.skip_reason == null) != (cb.skip_reason == null)) return false;
        }
    }
    return true;
}

/// Normalized, machine-readable benchmark summary counts (no volatile timing).
pub const BenchSummary = struct {
    total: u64,
    killed: u64,
    survived: u64,
    compile_error: u64,
    compiler_crash: u64,
    timeout: u64,
    skipped: u64,
    invalid: u64,
};

/// Deterministic equivalence verdicts proven by a benchmark smoke run. Each is
/// derived from `equivalentIgnoringTiming` over the relevant pair of runs.
pub const Equivalence = struct {
    cached_uncached: bool,
    serial_parallel: bool,
    cold_warm: bool,
};

/// Machine-readable, normalized benchmark output (docs/PERFORMANCE_STRATEGY.md):
/// a workload identity, the deterministic summary counts, and the equivalence
/// verdicts -- never wall-clock durations -- so it is stable for trend
/// comparison and snapshot testing.
pub const Benchmark = struct {
    schema_version: []const u8 = "zentinel.benchmark.v1",
    workload: []const u8,
    mutants: u64,
    summary: BenchSummary,
    equivalence: Equivalence,
};

/// Build a normalized benchmark record from a completed report and the proven
/// equivalence verdicts.
pub fn benchmark(workload: []const u8, rep: Report, equivalence: Equivalence) Benchmark {
    return .{
        .workload = workload,
        .mutants = rep.summary.total,
        .summary = .{
            .total = rep.summary.total,
            .killed = rep.summary.killed,
            .survived = rep.summary.survived,
            .compile_error = rep.summary.compile_error,
            .compiler_crash = rep.summary.compiler_crash,
            .timeout = rep.summary.timeout,
            .skipped = rep.summary.skipped,
            .invalid = rep.summary.invalid,
        },
        .equivalence = equivalence,
    };
}

/// Deterministic pretty-printed JSON for a benchmark record.
pub fn benchmarkToJson(arena: std.mem.Allocator, bench: Benchmark) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, bench, .{ .whitespace = .indent_2 });
}
