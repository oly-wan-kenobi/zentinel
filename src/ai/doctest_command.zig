// Layer: deterministic_core
//
// Advisory doctest-AI command engine (docs/DOCTEST_AI_INTEGRATION.md,
// docs/CLI_SPEC.md). Owns the deterministic plumbing behind the user-facing
// doctest AI subcommands `zentinel doctest explain|suggest|review-snapshot|
// suggest-missing`: it builds the `zentinel.ai.doctest.context.v1` packet for the
// four task-055 non-survivor flows, embeds it in the shared `zentinel.ai.prompt.v1`
// envelope, calls a deterministic stub provider, and validates the doctest
// suggestion / snapshot-review / explain responses with safety checks. Doctest AI
// is advisory only: it never decides pass/fail, never updates documentation,
// snapshots, or expected output, and never sets a deterministic doctest field. The
// deferred `explain_doctest_survivor` flow and `doctest_survivor`
// evidence are rejected here. Provider/option/redaction plumbing is reused from
// the mutation AI command engine (src/ai/command.zig).
const std = @import("std");
const command = @import("command.zig");
const context = @import("context.zig");
const redaction = @import("redaction.zig");
const provider = @import("provider.zig");

pub const Mode = command.Mode;
pub const Settings = command.Settings;
pub const Format = command.Format;
pub const Outcome = command.Outcome;

/// Default doctest-AI report path when `--input-report` is omitted (docs/CLI_SPEC.md).
pub const default_report_path = "zig-out/zentinel/doctest/report.json";

const prompt_instructions = [_][]const u8{
    "Use only provided context.",
    "Do not infer unavailable source.",
    "Do not decide doctest pass or fail.",
    "Do not update documentation, snapshots, or expected output.",
    "Return JSON only.",
};

pub const Flow = enum {
    explain_doctest_failure,
    suggest_doctest,
    review_snapshot,
    suggest_missing_doctests,
};

pub fn flowName(flow: Flow) []const u8 {
    return switch (flow) {
        .explain_doctest_failure => "explain_doctest_failure",
        .suggest_doctest => "suggest_doctest",
        .review_snapshot => "review_snapshot",
        .suggest_missing_doctests => "suggest_missing_doctests",
    };
}

/// The CLI usage-error detail for a doctest-AI subcommand invoked WITHOUT its
/// required positional, or null when the requirement is satisfied. `suggest` needs
/// `<doc-path>`; `explain` and `review-snapshot` need `<case-ref>`;
/// `suggest-missing` takes its target via `--file`, so it requires no positional.
/// Surfacing this as a usage error keeps a missing argument from being forwarded as
/// a null doc/case ref that the engine reports as an opaque DOC/CASE_NOT_FOUND.
pub fn missingPositional(flow: Flow, positional: ?[]const u8) ?[]const u8 {
    if (positional != null) return null;
    return switch (flow) {
        .suggest_doctest => "missing <doc-path>",
        .explain_doctest_failure, .review_snapshot => "missing <case-ref>",
        .suggest_missing_doctests => null,
    };
}

pub fn responseSchemaName(flow: Flow) []const u8 {
    return switch (flow) {
        .explain_doctest_failure => "zentinel.ai.explain.response.v1",
        .suggest_doctest, .suggest_missing_doctests => "zentinel.ai.doctest.suggest.response.v1",
        .review_snapshot => "zentinel.ai.doctest.snapshot_review.response.v1",
    };
}

/// AI-only and doctest-only command failures. The AI failures are shared with the
/// mutation engine; the two doctest failures carry their documented codes.
pub const Failure = command.Failure || error{ DoctestCaseNotFound, DoctestDocNotFound, DoctestSurvivorNotFound };
pub const RunError = Failure || error{OutOfMemory};

pub fn failureToken(err: Failure) []const u8 {
    return switch (err) {
        error.DoctestCaseNotFound => "ZNTL_DOCTEST_CASE_NOT_FOUND",
        error.DoctestDocNotFound => "ZNTL_DOCTEST_DOC_NOT_FOUND",
        error.DoctestSurvivorNotFound => "ZNTL_DOCTEST_SURVIVOR_NOT_FOUND",
        error.AiDisabled => "ZNTL_AI_DISABLED",
        error.AiProviderNotAllowed => "ZNTL_AI_PROVIDER_NOT_ALLOWED",
        error.AiReportNotFound => "ZNTL_AI_REPORT_NOT_FOUND",
        error.AiTargetNotFound => "ZNTL_AI_TARGET_NOT_FOUND",
        error.AiResponseInvalid => "ZNTL_AI_RESPONSE_INVALID",
    };
}

pub fn failureExit(err: Failure) u8 {
    _ = failureToken(err); // exhaustiveness guard
    return 2;
}

// --- JSON value helpers ----------------------------------------------------

fn eqStr(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn inSet(needle: []const u8, set: []const []const u8) bool {
    for (set) |x| if (eqStr(needle, x)) return true;
    return false;
}
fn objOf(v: std.json.Value) ?std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
        else => null,
    };
}
fn get(v: std.json.Value, key: []const u8) ?std.json.Value {
    return if (objOf(v)) |o| o.get(key) else null;
}
fn getO(v: ?std.json.Value, key: []const u8) ?std.json.Value {
    return if (v) |x| get(x, key) else null;
}
fn s(v: ?std.json.Value) []const u8 {
    if (v) |x| return switch (x) {
        .string => |t| t,
        else => "",
    };
    return "";
}
fn sOr(v: ?std.json.Value, d: []const u8) []const u8 {
    const t = s(v);
    return if (t.len == 0) d else t;
}
fn optStr(v: ?std.json.Value) ?[]const u8 {
    if (v) |x| return switch (x) {
        .string => |t| t,
        else => null,
    };
    return null;
}
fn requiredStr(v: ?std.json.Value) command.Failure![]const u8 {
    return optStr(v) orelse error.AiReportNotFound;
}
fn requiredBool(v: ?std.json.Value) command.Failure!bool {
    const x = v orelse return error.AiReportNotFound;
    return switch (x) {
        .bool => |b| b,
        else => error.AiReportNotFound,
    };
}
/// Narrow an optional report-sourced JSON integer to `?u32`. The report is
/// untrusted (`--input-report`), so a value above maxInt(u32) or a present
/// non-integer must become a clean invalid-report failure rather than a panicking
/// `@intCast` (abort in Debug/ReleaseSafe) or a silent wrap (ReleaseFast). Absent,
/// null, and negative values map to "no value" (null), preserving the prior
/// optional-field semantics.
fn optU32(v: ?std.json.Value) command.Failure!?u32 {
    const x = present(v) orelse return null;
    switch (x) {
        .integer => |n| {
            if (n < 0) return null;
            if (n > std.math.maxInt(u32)) return error.AiReportNotFound;
            return @intCast(n);
        },
        else => return error.AiReportNotFound,
    }
}
fn i64v(v: ?std.json.Value) i64 {
    if (v) |x| return switch (x) {
        .integer => |n| n,
        else => 0,
    };
    return 0;
}
fn arr(v: ?std.json.Value) ?[]std.json.Value {
    if (v) |x| return switch (x) {
        .array => |a| a.items,
        else => null,
    };
    return null;
}
/// Treat an absent field and an explicit JSON `null` the same: both are "no value".
fn present(v: ?std.json.Value) ?std.json.Value {
    const x = v orelse return null;
    return if (x == .null) null else x;
}
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
}

const mutation_runner_statuses = [_][]const u8{ "killed", "survived", "compile_error", "compiler_crash", "timeout", "skipped", "invalid" };
const runner_failure_kinds = [_][]const u8{ "none", "compile_error", "test_failure", "compiler_crash", "timeout", "skipped", "invalid" };

// --- Case-ref resolution ---------------------------------------------------

const SourceRef = struct { file: []const u8, line: i64 };

fn parseSourceRef(ref: []const u8) ?SourceRef {
    // "path:line" or "path:line:label". The path itself carries no colon.
    var it = std.mem.splitScalar(u8, ref, ':');
    const file = it.next() orelse return null;
    const line_str = it.next() orelse return null;
    const line = std.fmt.parseInt(i64, line_str, 10) catch return null;
    if (file.len == 0) return null;
    return .{ .file = file, .line = line };
}

/// Resolve `<case-ref>` against the selected doctest report only. A `dt_`-prefixed
/// ref matches a durable case id; any other ref is a source-ref selector resolved
/// against the case anchor line (`line_start`), never a secondary expectation
/// block, so a ref that points only at an expectation block does not resolve.
pub fn resolveCase(report: std.json.Value, ref: []const u8) ?std.json.Value {
    const cases = arr(get(report, "cases")) orelse return null;
    if (std.mem.startsWith(u8, ref, "dt_")) {
        for (cases) |c| if (eqStr(s(get(c, "id")), ref)) return c;
        return null;
    }
    for (cases) |c| if (eqStr(s(get(c, "source_ref")), ref)) return c;
    const parsed = parseSourceRef(ref) orelse return null;
    for (cases) |c| {
        if (eqStr(s(get(c, "file")), parsed.file) and i64v(get(c, "line_start")) == parsed.line) return c;
    }
    return null;
}

// --- Typed doctest context model -------------------------------------------

const Project = struct {
    name: []const u8,
    root_label: []const u8,
    zig_version: []const u8,
    zentinel_version: []const u8,
};
const Privacy = struct {
    remote_allowed: bool,
    source_context_policy: []const u8,
    redactions_applied: []const []const u8,
};
const DoctestMeta = struct {
    id: ?[]const u8,
    file: []const u8,
    line_start: ?u32,
    line_end: ?u32,
    source_ref: ?[]const u8,
    block_refs: []const []const u8,
    kind: []const u8,
    status: []const u8,
};
const CommandEv = struct {
    original: []const u8,
    argv: []const []const u8,
    cwd: []const u8,
    environment_policy: []const u8 = "minimal",
    shell: bool = false,
};
const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    file: ?[]const u8,
    line: ?u32,
    column: ?u32,
};
const SnapshotEv = struct {
    expected_excerpt: []const u8,
    actual_excerpt: []const u8,
    normalized_expected_excerpt: []const u8,
    normalized_actual_excerpt: []const u8,
    match_mode: []const u8,
    expected_block_ref: ?[]const u8,
    actual_ref: []const u8,
    matched: bool,
};
const DocsMetadata = struct {
    public: bool,
    has_doctests: bool,
    executable_case_count: u32,
    nearest_heading: ?[]const u8,
};
const ReportSummary = struct {
    total: u64,
    passed: u64,
    failed: u64,
    compile_error: u64,
    expected_compile_error: u64,
    timeout: u64,
    skipped: u64,
    invalid: u64,
};
const DocsEntry = struct {
    file: []const u8,
    public: bool,
    has_doctests: bool,
    executable_case_count: u32,
};
const Candidate = struct {
    file: []const u8,
    heading: []const u8,
    line_hint: ?u32,
    reason: []const u8,
    missing_kind: []const u8,
};

const CaseFailureEvidence = struct {
    kind: []const u8 = "case_failure",
    status: []const u8,
    command: ?CommandEv,
    expected_excerpt: ?[]const u8,
    actual_excerpt: ?[]const u8,
    normalized_expected_excerpt: ?[]const u8,
    normalized_actual_excerpt: ?[]const u8,
    diagnostics: []const Diagnostic,
    failure_summary: []const u8,
};
const SnapshotDiffEvidence = struct {
    kind: []const u8 = "snapshot_diff",
    case_status: []const u8,
    snapshot: SnapshotEv,
};
const DocsTargetEvidence = struct {
    kind: []const u8 = "docs_target",
    target_file: []const u8,
    heading_context: []const []const u8,
    docs_metadata: DocsMetadata,
    report_summary: ?ReportSummary,
};
const MissingEvidence = struct {
    kind: []const u8 = "missing_doctests",
    docs: []const DocsEntry,
    candidates: []const Candidate,
};

fn DoctestContext(comptime Evidence: type) type {
    return struct {
        schema_version: []const u8 = "zentinel.ai.doctest.context.v1",
        flow: []const u8,
        created_by: []const u8 = "zentinel",
        provider_mode: []const u8,
        project: Project,
        doctest: DoctestMeta,
        evidence: Evidence,
        privacy: Privacy,
    };
}

pub const ContextInput = struct {
    case: ?std.json.Value = null,
    doc_path: ?[]const u8 = null,
    report: ?std.json.Value = null,
};

fn projectOf(arena: std.mem.Allocator, settings: Settings, report: ?std.json.Value, patterns: []const []const u8, log: *context.RedactionLog) redaction.Error!Project {
    const run_info = if (report) |r| get(r, "run") else null;
    return .{
        .name = try context.redactField(arena, settings.project_name, patterns, log),
        .root_label = "<project>",
        .zig_version = try context.redactField(arena, sOr(getO(run_info, "zig_version"), settings.zig_version), patterns, log),
        .zentinel_version = try context.redactField(arena, sOr(getO(run_info, "zentinel_version"), settings.zentinel_version), patterns, log),
    };
}
fn privacyOf(settings: Settings, log: *context.RedactionLog) Privacy {
    return .{ .remote_allowed = settings.remote_allowed, .source_context_policy = "minimal", .redactions_applied = log.applied() };
}

/// Redact a doctest meta's path-bearing fields (file, source_ref) through the
/// path-normalize + secret-scrub pass, recording redactions into `log` (F-4).
fn redactedMeta(arena: std.mem.Allocator, meta_in: DoctestMeta, patterns: []const []const u8, log: *context.RedactionLog) redaction.Error!DoctestMeta {
    var meta = meta_in;
    meta.file = try context.redactField(arena, meta.file, patterns, log);
    if (meta.source_ref) |sr| meta.source_ref = try context.redactField(arena, sr, patterns, log);
    // The doctest id is a free-form report string under an untrusted --input-report
    // (the validator only prefix-checks it), so scrub it like file/source_ref so a
    // path/secret in its suffix cannot reach the provider via doctest.id.
    if (meta.id) |id| meta.id = try context.redactField(arena, id, patterns, log);
    // `status` is a free-string schema field sourced from the report; scrub it too
    // (kind is enum-gated by validateContext, so it needs no redaction).
    meta.status = try context.redactField(arena, meta.status, patterns, log);
    return meta;
}

fn readStrArray(arena: std.mem.Allocator, v: ?std.json.Value) ![]const []const u8 {
    const items = arr(v) orelse return &.{};
    const buf = try arena.alloc([]const u8, items.len);
    for (items, 0..) |it, idx| buf[idx] = switch (it) {
        .string => |t| t,
        else => "",
    };
    return buf;
}

fn readRequiredRedactedStrArray(arena: std.mem.Allocator, v: ?std.json.Value, patterns: []const []const u8, log: *context.RedactionLog) (redaction.Error || command.Failure)![]const []const u8 {
    const items = arr(v) orelse return error.AiReportNotFound;
    if (items.len == 0) return error.AiReportNotFound;
    const buf = try arena.alloc([]const u8, items.len);
    for (items, 0..) |it, idx| {
        const text: []const u8 = switch (it) {
            .string => |t| t,
            else => return error.AiReportNotFound,
        };
        buf[idx] = try context.redactField(arena, text, patterns, log);
    }
    return buf;
}

fn readCommand(arena: std.mem.Allocator, v: ?std.json.Value, patterns: []const []const u8, log: *context.RedactionLog) (redaction.Error || command.Failure)!?CommandEv {
    const o = v orelse return null;
    if (objOf(o) == null) return null;
    const environment_policy = try requiredStr(get(o, "environment_policy"));
    if (!eqStr(environment_policy, "minimal")) return error.AiReportNotFound;
    const shell = try requiredBool(get(o, "shell"));
    if (shell) return error.AiReportNotFound;
    return CommandEv{
        .original = try context.redactField(arena, try requiredStr(get(o, "original")), patterns, log),
        .argv = try readRequiredRedactedStrArray(arena, get(o, "argv"), patterns, log),
        .cwd = try context.redactField(arena, try requiredStr(get(o, "cwd")), patterns, log),
        .environment_policy = environment_policy,
        .shell = shell,
    };
}
fn readDiagnostics(arena: std.mem.Allocator, case: std.json.Value, patterns: []const []const u8, log: *context.RedactionLog) (redaction.Error || command.Failure)![]const Diagnostic {
    const items = arr(get(case, "diagnostics")) orelse return &.{};
    const buf = try arena.alloc(Diagnostic, items.len);
    for (items, 0..) |it, idx| buf[idx] = .{
        // `code` is a free-form report string under an untrusted --input-report
        // and has no schema maxLength, so scrub it like message/file rather than
        // let a secret reach the provider verbatim.
        .code = try context.redactField(arena, s(get(it, "code")), patterns, log),
        .message = try context.redactField(arena, s(get(it, "message")), patterns, log),
        .file = if (optStr(get(it, "file"))) |f| try context.redactField(arena, f, patterns, log) else null,
        .line = try optU32(get(it, "line")),
        .column = try optU32(get(it, "column")),
    };
    return buf;
}
fn redactOpt(arena: std.mem.Allocator, v: ?std.json.Value, patterns: []const []const u8, log: *context.RedactionLog) redaction.Error!?[]const u8 {
    const t = optStr(v) orelse return null;
    return try context.redactAndCapLogged(arena, t, patterns, context.excerpt_limit, log);
}

fn metaFromCase(case: std.json.Value) command.Failure!DoctestMeta {
    return .{
        .id = optStr(get(case, "id")),
        .file = s(get(case, "file")),
        .line_start = try optU32(get(case, "line_start")),
        .line_end = try optU32(get(case, "line_end")),
        .source_ref = optStr(get(case, "source_ref")),
        .block_refs = &.{},
        .kind = sOr(get(case, "kind"), "cli"),
        .status = sOr(get(case, "status"), "failed"),
    };
}
fn docsTargetMeta(doc_path: ?[]const u8) DoctestMeta {
    return .{
        .id = null,
        .file = doc_path orelse "docs/",
        .line_start = null,
        .line_end = null,
        .source_ref = null,
        .block_refs = &.{},
        .kind = "docs_target",
        .status = "not_applicable",
    };
}

fn isPublicDoc(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "docs/");
}
fn missingKindFor(path: []const u8) []const u8 {
    if (std.mem.indexOf(u8, path, "CONFIG") != null) return "config";
    if (std.mem.indexOf(u8, path, "CLI") != null) return "cli";
    if (std.mem.indexOf(u8, path, "REPORT") != null) return "report";
    if (std.mem.indexOf(u8, path, "MUTATOR") != null) return "mutation";
    return "zig_test";
}

/// Build the doctest AI context as a validated JSON value for the given flow.
pub fn buildContextValue(arena: std.mem.Allocator, flow: Flow, mode: Mode, input: ContextInput, settings: Settings) !std.json.Value {
    const patterns = settings.redact_patterns;
    const provider_mode = provider.modeName(mode);
    // Accumulates redactions across every field of the selected flow so
    // privacy.redactions_applied is truthful (audit F-4). Only one switch arm
    // runs, so a single log spans that arm's evidence, meta, and doc fields.
    var log = context.RedactionLog.init(arena);
    const bytes = switch (flow) {
        .explain_doctest_failure => blk: {
            const case = input.case orelse return error.DoctestCaseNotFound;
            const result = get(case, "result");
            const snapshot = getO(result, "snapshot");
            const command_ev = try readCommand(arena, get(case, "command"), patterns, &log);
            const ev = CaseFailureEvidence{
                .status = try context.redactField(arena, sOr(get(case, "status"), "failed"), patterns, &log),
                .command = command_ev,
                .expected_excerpt = try redactOpt(arena, getO(snapshot, "expected_excerpt"), patterns, &log),
                .actual_excerpt = try redactOpt(arena, getO(snapshot, "actual_excerpt"), patterns, &log),
                .normalized_expected_excerpt = try redactOpt(arena, getO(snapshot, "normalized_expected_excerpt"), patterns, &log),
                .normalized_actual_excerpt = try redactOpt(arena, getO(snapshot, "normalized_actual_excerpt"), patterns, &log),
                .diagnostics = try readDiagnostics(arena, case, patterns, &log),
                .failure_summary = try context.redactAndCapLogged(arena, s(getO(result, "failure_summary")), patterns, context.excerpt_limit, &log),
            };
            const meta = try redactedMeta(arena, try metaFromCase(case), patterns, &log);
            const ctx = DoctestContext(CaseFailureEvidence){
                .flow = flowName(flow),
                .provider_mode = provider_mode,
                .project = try projectOf(arena, settings, input.report, patterns, &log),
                .doctest = meta,
                .evidence = ev,
                .privacy = privacyOf(settings, &log),
            };
            break :blk try std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
        },
        .review_snapshot => blk: {
            const case = input.case orelse return error.DoctestCaseNotFound;
            const snap = present(getO(get(case, "result"), "snapshot")) orelse return error.DoctestCaseNotFound;
            const ev = SnapshotDiffEvidence{
                .case_status = try context.redactField(arena, sOr(get(case, "status"), "failed"), patterns, &log),
                .snapshot = .{
                    .expected_excerpt = try context.redactAndCapLogged(arena, s(get(snap, "expected_excerpt")), patterns, context.excerpt_limit, &log),
                    .actual_excerpt = try context.redactAndCapLogged(arena, s(get(snap, "actual_excerpt")), patterns, context.excerpt_limit, &log),
                    .normalized_expected_excerpt = try context.redactAndCapLogged(arena, s(get(snap, "normalized_expected_excerpt")), patterns, context.excerpt_limit, &log),
                    .normalized_actual_excerpt = try context.redactAndCapLogged(arena, s(get(snap, "normalized_actual_excerpt")), patterns, context.excerpt_limit, &log),
                    .match_mode = try context.redactField(arena, sOr(get(snap, "match_mode"), "exact"), patterns, &log),
                    .expected_block_ref = if (optStr(get(snap, "expected_block_ref"))) |ref| try context.redactField(arena, ref, patterns, &log) else null,
                    .actual_ref = try context.redactField(arena, sOr(get(snap, "actual_ref"), "stdout"), patterns, &log),
                    .matched = switch (get(snap, "matched") orelse std.json.Value{ .bool = false }) {
                        .bool => |b| b,
                        else => false,
                    },
                },
            };
            const meta = try redactedMeta(arena, try metaFromCase(case), patterns, &log);
            const ctx = DoctestContext(SnapshotDiffEvidence){
                .flow = flowName(flow),
                .provider_mode = provider_mode,
                .project = try projectOf(arena, settings, input.report, patterns, &log),
                .doctest = meta,
                .evidence = ev,
                .privacy = privacyOf(settings, &log),
            };
            break :blk try std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
        },
        .suggest_doctest => blk: {
            const doc = input.doc_path orelse return error.DoctestDocNotFound;
            const doc_red = try context.redactField(arena, doc, patterns, &log);
            const ev = DocsTargetEvidence{
                .target_file = doc_red,
                .heading_context = &.{},
                .docs_metadata = .{ .public = isPublicDoc(doc), .has_doctests = false, .executable_case_count = 0, .nearest_heading = null },
                .report_summary = null,
            };
            const ctx = DoctestContext(DocsTargetEvidence){
                .flow = flowName(flow),
                .provider_mode = provider_mode,
                .project = try projectOf(arena, settings, input.report, patterns, &log),
                .doctest = docsTargetMeta(doc_red),
                .evidence = ev,
                .privacy = privacyOf(settings, &log),
            };
            break :blk try std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
        },
        .suggest_missing_doctests => blk: {
            const doc = input.doc_path orelse "docs/";
            const doc_red = try context.redactField(arena, doc, patterns, &log);
            const docs = try arena.alloc(DocsEntry, 1);
            docs[0] = .{ .file = doc_red, .public = isPublicDoc(doc), .has_doctests = false, .executable_case_count = 0 };
            const candidates = try arena.alloc(Candidate, 1);
            candidates[0] = .{ .file = doc_red, .heading = "", .line_hint = null, .reason = "Public docs path lacks an executable doctest block.", .missing_kind = missingKindFor(doc) };
            const ev = MissingEvidence{ .docs = docs, .candidates = candidates };
            const ctx = DoctestContext(MissingEvidence){
                .flow = flowName(flow),
                .provider_mode = provider_mode,
                .project = try projectOf(arena, settings, input.report, patterns, &log),
                .doctest = docsTargetMeta(doc_red),
                .evidence = ev,
                .privacy = privacyOf(settings, &log),
            };
            break :blk try std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
        },
    };
    return std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
}

// --- Prompt envelope -------------------------------------------------------

const Prompt = struct {
    schema_version: []const u8 = "zentinel.ai.prompt.v1",
    flow: []const u8,
    instructions: []const []const u8,
    context: std.json.Value,
    response_schema: struct { name: []const u8 },
};

pub fn buildPromptValue(arena: std.mem.Allocator, flow: Flow, ctx: std.json.Value) !std.json.Value {
    const prompt = Prompt{
        .flow = flowName(flow),
        .instructions = &prompt_instructions,
        .context = ctx,
        .response_schema = .{ .name = responseSchemaName(flow) },
    };
    const bytes = try std.json.Stringify.valueAlloc(arena, prompt, .{ .whitespace = .indent_2 });
    return std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
}

// --- Context validation ----------------------------------------------------

pub const ContextViolation = enum {
    ok,
    not_object,
    missing_field,
    bad_enum,
    survivor_flow,
    bad_evidence,
};

const doctest_flows = [_][]const u8{ "explain_doctest_failure", "suggest_doctest", "review_snapshot", "suggest_missing_doctests" };
const evidence_kinds = [_][]const u8{ "case_failure", "docs_target", "snapshot_diff", "missing_doctests" };
/// `doctest.kind` is a schema enum; gate it like the mutation context gates its
/// enum fields so an unredacted free string there fails closed.
const doctest_kinds = [_][]const u8{ "zig_compile_pass", "zig_test", "zig_compile_fail", "cli", "config", "config_fail", "mutation", "docs_target" };

fn requireKeys(obj: std.json.ObjectMap, keys: []const []const u8) bool {
    for (keys) |k| if (obj.get(k) == null) return false;
    return true;
}
fn onlyKeys(obj: std.json.ObjectMap, allowed: []const []const u8) bool {
    for (obj.keys()) |k| if (!inSet(k, allowed)) return false;
    return true;
}
fn enumOk(obj: std.json.ObjectMap, key: []const u8, set: []const []const u8) bool {
    const v = obj.get(key) orelse return false;
    return switch (v) {
        .string => |t| inSet(t, set),
        else => false,
    };
}

/// Structural validator for `zentinel.ai.doctest.context.v1`. Rejects the deferred
/// survivor flow and a `doctest_survivor` evidence kind.
pub fn validateContext(value: std.json.Value) ContextViolation {
    const obj = objOf(value) orelse return .not_object;
    if (!requireKeys(obj, &.{ "schema_version", "flow", "created_by", "provider_mode", "project", "doctest", "evidence", "privacy" })) return .missing_field;
    if (!enumOk(obj, "schema_version", &.{"zentinel.ai.doctest.context.v1"})) return .bad_enum;
    const flow = s(obj.get("flow"));
    if (eqStr(flow, "explain_doctest_survivor")) return .survivor_flow;
    if (!inSet(flow, &doctest_flows)) return .bad_enum;
    if (!enumOk(obj, "created_by", &.{"zentinel"})) return .bad_enum;
    if (!enumOk(obj, "provider_mode", &.{ "disabled", "stub", "local", "remote" })) return .bad_enum;

    const ev = objOf(obj.get("evidence").?) orelse return .not_object;
    const kind = s(ev.get("kind"));
    if (eqStr(kind, "doctest_survivor")) return .survivor_flow;
    if (!inSet(kind, &evidence_kinds)) return .bad_evidence;

    const project = objOf(obj.get("project").?) orelse return .not_object;
    if (!requireKeys(project, &.{ "name", "root_label", "zig_version", "zentinel_version" })) return .missing_field;
    const doctest = objOf(obj.get("doctest").?) orelse return .not_object;
    if (!requireKeys(doctest, &.{ "id", "file", "line_start", "line_end", "source_ref", "block_refs", "kind", "status" })) return .missing_field;
    if (!enumOk(doctest, "kind", &doctest_kinds)) return .bad_enum;
    const privacy = objOf(obj.get("privacy").?) orelse return .not_object;
    if (!requireKeys(privacy, &.{ "remote_allowed", "source_context_policy", "redactions_applied" })) return .missing_field;
    return .ok;
}

pub const PromptViolation = enum {
    ok,
    not_object,
    missing_field,
    bad_schema_version,
    bad_flow,
    survivor_flow,
    no_instructions,
    bad_context,
    unknown_context_schema,
    bad_response_schema,
};

pub fn validatePrompt(value: std.json.Value) PromptViolation {
    const obj = objOf(value) orelse return .not_object;
    if (!requireKeys(obj, &.{ "schema_version", "flow", "instructions", "context", "response_schema" })) return .missing_field;
    if (!eqStr(s(obj.get("schema_version")), "zentinel.ai.prompt.v1")) return .bad_schema_version;
    const flow_name = s(obj.get("flow"));
    if (eqStr(flow_name, "explain_doctest_survivor")) return .survivor_flow;
    if (!inSet(flow_name, &doctest_flows)) return .bad_flow;
    const flow = parseFlowName(flow_name).?;
    const instr = arr(obj.get("instructions")) orelse return .no_instructions;
    if (instr.len == 0) return .no_instructions;

    const ctx = obj.get("context").?;
    const ctx_obj = objOf(ctx) orelse return .bad_context;
    if (eqStr(s(ctx_obj.get("schema_version")), "zentinel.ai.doctest.context.v1")) {
        if (validateContext(ctx) != .ok) return .bad_context;
    } else {
        return .unknown_context_schema;
    }
    const rs = objOf(obj.get("response_schema").?) orelse return .bad_response_schema;
    if (!eqStr(s(rs.get("name")), responseSchemaName(flow))) return .bad_response_schema;
    return .ok;
}

fn parseFlowName(name: []const u8) ?Flow {
    if (eqStr(name, "explain_doctest_failure")) return .explain_doctest_failure;
    if (eqStr(name, "suggest_doctest")) return .suggest_doctest;
    if (eqStr(name, "review_snapshot")) return .review_snapshot;
    if (eqStr(name, "suggest_missing_doctests")) return .suggest_missing_doctests;
    return null;
}

// --- Typed responses + deterministic stub ----------------------------------

const EvidenceRef = struct { kind: []const u8, ref: []const u8 };
const ExplainResponse = struct {
    schema_version: []const u8 = "zentinel.ai.explain.response.v1",
    classification: []const u8,
    confidence: []const u8,
    summary: []const u8,
    evidence_refs: []const EvidenceRef,
    next_action: []const u8,
};
const Suggestion = struct {
    target_file: []const u8,
    line_hint: ?u32,
    reason: []const u8,
    block: []const u8,
};
const SuggestResponse = struct {
    schema_version: []const u8 = "zentinel.ai.doctest.suggest.response.v1",
    suggestions: []const Suggestion,
};
const SnapshotReviewResponse = struct {
    schema_version: []const u8 = "zentinel.ai.doctest.snapshot_review.response.v1",
    classification: []const u8,
    summary: []const u8,
    risk: []const u8,
    evidence_refs: []const EvidenceRef,
    next_action: []const u8,
};

const Response = union(enum) {
    explain: ExplainResponse,
    suggest: SuggestResponse,
    snapshot_review: SnapshotReviewResponse,
};

fn explainClassification(status: []const u8) []const u8 {
    if (eqStr(status, "failed")) return "doctest_output_mismatch";
    if (eqStr(status, "compile_error")) return "doctest_invalid_example";
    if (eqStr(status, "invalid")) return "doctest_invalid_example";
    return "unclear";
}

fn stubExplain(arena: std.mem.Allocator, case: std.json.Value, patterns: []const []const u8) redaction.Error!Response {
    const status = s(get(case, "status"));
    const classification = explainClassification(status);
    const id = s(get(case, "id"));
    // Redact the file the stub echoes into its advisory text (F-4).
    var sink = context.RedactionLog.init(arena);
    const file = try context.redactField(arena, s(get(case, "file")), patterns, &sink);
    const refs = try arena.alloc(EvidenceRef, 1);
    refs[0] = .{ .kind = "doctest_case", .ref = id };
    return .{ .explain = .{
        .classification = classification,
        .confidence = if (eqStr(classification, "unclear")) "unclear" else "medium",
        .summary = try std.fmt.allocPrint(arena, "Doctest case {s} in {s} is {s}; the stub classifies it as {s}.", .{ id, file, status, classification }),
        .evidence_refs = refs,
        .next_action = "Compare the normalized expected and actual output and update the example only after human review.",
    } };
}

fn supportedBlock(doc_path: []const u8) []const u8 {
    if (std.mem.indexOf(u8, doc_path, "CONFIG") != null) return "```toml config\n[project]\nname = \"example\"\n\n[test]\ncommands = [\"zig build test\"]\n```";
    return "```bash cli\nzentinel version\n```";
}

fn stubSuggest(arena: std.mem.Allocator, doc_path: []const u8, patterns: []const []const u8) redaction.Error!Response {
    var sink = context.RedactionLog.init(arena);
    const target = try context.redactField(arena, doc_path, patterns, &sink);
    const suggestions = try arena.alloc(Suggestion, 1);
    suggestions[0] = .{
        .target_file = target,
        .line_hint = null,
        .reason = "This public documentation path should carry an executable doctest block.",
        .block = supportedBlock(doc_path),
    };
    return .{ .suggest = .{ .suggestions = suggestions } };
}

fn snapshotClassification(expected: []const u8, actual: []const u8) []const u8 {
    if (eqStr(expected, actual)) return "unclear";
    if (containsIgnoreCase(actual, expected) or containsIgnoreCase(expected, actual)) return "wording_change";
    return "semantic_change";
}

fn stubSnapshotReview(arena: std.mem.Allocator, case: std.json.Value, patterns: []const []const u8) redaction.Error!Response {
    const snap = getO(get(case, "result"), "snapshot");
    const expected = s(getO(snap, "normalized_expected_excerpt"));
    const actual = s(getO(snap, "normalized_actual_excerpt"));
    const classification = snapshotClassification(expected, actual);
    const risk: []const u8 = if (eqStr(classification, "semantic_change")) "high" else if (eqStr(classification, "wording_change")) "medium" else "low";
    // The block ref can be a source_ref path; redact it before it is echoed (F-4).
    var sink = context.RedactionLog.init(arena);
    const block_ref = try context.redactField(arena, optStr(getO(snap, "expected_block_ref")) orelse s(get(case, "source_ref")), patterns, &sink);
    const refs = try arena.alloc(EvidenceRef, 1);
    refs[0] = .{ .kind = "block_ref", .ref = block_ref };
    return .{ .snapshot_review = .{
        .classification = classification,
        .summary = try std.fmt.allocPrint(arena, "Normalized expected and actual output differ ({s}).", .{classification}),
        .risk = risk,
        .evidence_refs = refs,
        .next_action = "Review the public wording before updating the expected output block; do not auto-apply.",
    } };
}

fn responseJson(arena: std.mem.Allocator, response: Response) ![]u8 {
    const opts = std.json.Stringify.Options{ .whitespace = .indent_2 };
    return switch (response) {
        .explain => |r| std.json.Stringify.valueAlloc(arena, r, opts),
        .suggest => |r| std.json.Stringify.valueAlloc(arena, r, opts),
        .snapshot_review => |r| std.json.Stringify.valueAlloc(arena, r, opts),
    };
}

// --- Response validation ---------------------------------------------------

pub const ResponseViolation = enum {
    ok,
    not_object,
    not_array,
    missing_field,
    unknown_field,
    bad_schema_version,
    bad_enum,
    empty_summary,
    too_many_suggestions,
    bad_path,
    unsafe_text,
};

const unsafe_markers = [_][]const u8{
    "ignore previous", "ignore all previous", "disregard previous",
    "<tool",           "</tool",              "```tool",
    "system:",         "<|",                  "begin_of_text",
};
fn unsafeText(text: []const u8) bool {
    for (unsafe_markers) |m| if (std.ascii.indexOfIgnoreCase(text, m) != null) return true;
    return false;
}
fn projectRelative(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/' or path[0] == '~' or path[0] == '\\') return false;
    if (path.len >= 2 and path[1] == ':') return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    return true;
}

const snapshot_classifications = [_][]const u8{ "wording_change", "formatting_change", "normalization_change", "semantic_change", "unclear" };
const risks = [_][]const u8{ "low", "medium", "high", "unclear" };

pub fn validateSuggestResponse(value: std.json.Value) ResponseViolation {
    const obj = objOf(value) orelse return .not_object;
    const allowed = [_][]const u8{ "schema_version", "suggestions" };
    if (!requireKeys(obj, &allowed)) return .missing_field;
    if (!onlyKeys(obj, &allowed)) return .unknown_field;
    if (!eqStr(s(obj.get("schema_version")), "zentinel.ai.doctest.suggest.response.v1")) return .bad_schema_version;
    const suggestions = arr(obj.get("suggestions")) orelse return .not_array;
    if (suggestions.len == 0) return .missing_field;
    if (suggestions.len > 3) return .too_many_suggestions;
    const fields = [_][]const u8{ "target_file", "line_hint", "reason", "block" };
    for (suggestions) |sg| {
        const o = objOf(sg) orelse return .not_object;
        if (!requireKeys(o, &fields)) return .missing_field;
        if (!onlyKeys(o, &fields)) return .unknown_field;
        if (!projectRelative(s(o.get("target_file")))) return .bad_path;
        if (s(o.get("reason")).len == 0) return .empty_summary;
        if (s(o.get("block")).len == 0) return .missing_field;
        if (unsafeText(s(o.get("reason"))) or unsafeText(s(o.get("block")))) return .unsafe_text;
    }
    return .ok;
}

pub fn validateSnapshotReviewResponse(value: std.json.Value) ResponseViolation {
    const obj = objOf(value) orelse return .not_object;
    const allowed = [_][]const u8{ "schema_version", "classification", "summary", "risk", "evidence_refs", "next_action" };
    if (!requireKeys(obj, &allowed)) return .missing_field;
    if (!onlyKeys(obj, &allowed)) return .unknown_field;
    if (!eqStr(s(obj.get("schema_version")), "zentinel.ai.doctest.snapshot_review.response.v1")) return .bad_schema_version;
    if (!inSet(s(obj.get("classification")), &snapshot_classifications)) return .bad_enum;
    if (!inSet(s(obj.get("risk")), &risks)) return .bad_enum;
    if (s(obj.get("summary")).len == 0) return .empty_summary;
    if (s(obj.get("next_action")).len == 0) return .missing_field;
    if (unsafeText(s(obj.get("summary"))) or unsafeText(s(obj.get("next_action")))) return .unsafe_text;
    const refs = arr(obj.get("evidence_refs")) orelse return .not_array;
    for (refs) |r| {
        const o = objOf(r) orelse return .not_object;
        if (!requireKeys(o, &.{ "kind", "ref" })) return .missing_field;
        if (!onlyKeys(o, &.{ "kind", "ref" })) return .unknown_field;
        if (unsafeText(s(o.get("ref")))) return .unsafe_text;
    }
    return .ok;
}

fn responseOk(flow: Flow, value: std.json.Value) bool {
    return switch (flow) {
        .explain_doctest_failure => command.validateResponse(.explain, value) == .ok,
        .review_snapshot => validateSnapshotReviewResponse(value) == .ok,
        .suggest_doctest, .suggest_missing_doctests => validateSuggestResponse(value) == .ok,
    };
}

// --- Top-level run ---------------------------------------------------------

pub const Input = struct {
    flow: Flow,
    case_ref: ?[]const u8,
    doc_path: ?[]const u8,
    doc_exists: bool,
    provider_override: ?Mode,
    report_json: ?[]const u8,
    settings: Settings,
};

pub fn run(arena: std.mem.Allocator, input: Input, format: Format) RunError!Outcome {
    const mode = try command.resolveMode(input.settings, input.provider_override);

    var ctx_input: ContextInput = .{};
    const response: Response = switch (input.flow) {
        .explain_doctest_failure, .review_snapshot => blk: {
            const bytes = input.report_json orelse return error.AiReportNotFound;
            const report = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch return error.AiReportNotFound;
            if (objOf(report) == null or get(report, "cases") == null) return error.AiReportNotFound;
            const ref = input.case_ref orelse return error.DoctestCaseNotFound;
            const case = resolveCase(report, ref) orelse return error.DoctestCaseNotFound;
            if (input.flow == .review_snapshot and present(getO(get(case, "result"), "snapshot")) == null) return error.DoctestCaseNotFound;
            ctx_input = .{ .case = case, .report = report };
            break :blk if (input.flow == .explain_doctest_failure)
                (stubExplain(arena, case, input.settings.redact_patterns) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.RedactionFailed => return error.AiResponseInvalid,
                })
            else
                (stubSnapshotReview(arena, case, input.settings.redact_patterns) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.RedactionFailed => return error.AiResponseInvalid,
                });
        },
        .suggest_doctest => blk: {
            const doc = input.doc_path orelse return error.DoctestDocNotFound;
            if (!input.doc_exists) return error.DoctestDocNotFound;
            const report: ?std.json.Value = if (input.report_json) |b|
                (std.json.parseFromSliceLeaky(std.json.Value, arena, b, .{}) catch null)
            else
                null;
            ctx_input = .{ .doc_path = doc, .report = report };
            break :blk stubSuggest(arena, doc, input.settings.redact_patterns) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.RedactionFailed => return error.AiResponseInvalid,
            };
        },
        .suggest_missing_doctests => blk: {
            if (input.doc_path) |d| {
                if (!input.doc_exists) return error.DoctestDocNotFound;
                ctx_input = .{ .doc_path = d };
            }
            break :blk stubSuggest(arena, input.doc_path orelse "docs/", input.settings.redact_patterns) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                error.RedactionFailed => return error.AiResponseInvalid,
            };
        },
    };

    // Build, validate the doctest context and prompt envelope before "sending".
    const ctx = buildContextValue(arena, input.flow, mode, ctx_input, input.settings) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        // An out-of-range or non-integer report integer is an invalid report.
        error.AiReportNotFound => return error.AiReportNotFound,
        else => return error.AiResponseInvalid,
    };
    if (validateContext(ctx) != .ok) return error.AiResponseInvalid;
    const prompt = buildPromptValue(arena, input.flow, ctx) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.AiResponseInvalid,
    };
    if (validatePrompt(prompt) != .ok) return error.AiResponseInvalid;

    // Validate the response before rendering.
    const json = try responseJson(arena, response);
    const value = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch return error.AiResponseInvalid;
    if (!responseOk(input.flow, value)) return error.AiResponseInvalid;

    const body = switch (format) {
        .json => json,
        .text => try renderText(arena, response),
    };
    return .{ .exit_code = 0, .body = body, .format = format };
}

fn renderText(arena: std.mem.Allocator, response: Response) ![]u8 {
    return switch (response) {
        .explain => |r| std.fmt.allocPrint(arena, "classification: {s}\nconfidence: {s}\nsummary: {s}\nnext action: {s}\n", .{ r.classification, r.confidence, r.summary, r.next_action }),
        .snapshot_review => |r| std.fmt.allocPrint(arena, "classification: {s}\nrisk: {s}\nsummary: {s}\nnext action: {s}\n", .{ r.classification, r.risk, r.summary, r.next_action }),
        .suggest => |r| blk: {
            var body = try std.fmt.allocPrint(arena, "suggestions: {d}\n", .{r.suggestions.len});
            for (r.suggestions, 0..) |sg, idx| {
                body = try std.fmt.allocPrint(arena, "{s}{d}. {s}\n   reason: {s}\n", .{ body, idx + 1, sg.target_file, sg.reason });
            }
            break :blk body;
        },
    };
}

// ===========================================================================
// Survivor flow: advisory explanation for a mutation-aware doctest
// survivor. This is a SEPARATE path from the four task-055 non-survivor flows.
// `validateContext`/`validatePrompt`/`run`/`Flow` are intentionally unchanged
// and still treat `explain_doctest_survivor` as their out-of-scope flow; the
// functions below own the survivor flow. AI stays advisory only: this reads
// deterministic `zentinel doctest --mutate` report evidence and never changes a
// survivor's status, the report, a snapshot, or any documentation.
// ===========================================================================

const RunnerEvidence = struct {
    status: []const u8,
    command: ?CommandEv,
    exit_code: ?i64,
    timed_out: bool,
    failure_kind: []const u8,
    stdout_excerpt: []const u8,
    stderr_excerpt: []const u8,
    failure_summary: []const u8,
    skip_reason: ?[]const u8,
};
const SourceCase = struct {
    doctest_case_id: ?[]const u8,
    file: []const u8,
    source_ref: ?[]const u8,
};
const MutationCase = struct {
    case_id: []const u8,
    mutant_id: []const u8,
    operator: []const u8,
    mutated_diff: []const []const u8,
    backend_stability: []const u8,
    runner_evidence: RunnerEvidence,
};
const SurvivorEvidence = struct {
    kind: []const u8 = "doctest_survivor",
    survivor_ref: []const u8,
    source_case: SourceCase,
    mutation_case: MutationCase,
};

/// Resolve `<survivor-ref>` against the selected mutation-aware doctest report.
/// Matches only a `survived` case whose `mutation.survivor_ref` is a non-null
/// `ds_` value equal to `ref`; killed, skipped, invalid, compile-error,
/// compiler-crash, and timeout documentation mutants never resolve.
pub fn resolveSurvivor(report: std.json.Value, ref: []const u8) ?std.json.Value {
    const cases = arr(get(report, "cases")) orelse return null;
    for (cases) |c| {
        if (!eqStr(s(get(c, "status")), "survived")) continue;
        const mutation = present(get(c, "mutation")) orelse continue;
        const sref = optStr(present(get(mutation, "survivor_ref"))) orelse continue;
        if (eqStr(sref, ref)) return c;
    }
    return null;
}

fn readRunnerEvidence(arena: std.mem.Allocator, mutation: std.json.Value, patterns: []const []const u8, log: *context.RedactionLog) !RunnerEvidence {
    const re = present(get(mutation, "runner_evidence")) orelse return error.AiReportNotFound;
    const cmd = try readCommand(arena, get(re, "command"), patterns, log) orelse return error.AiReportNotFound;
    const status = try requiredStr(get(re, "status"));
    const timed_out = try requiredBool(get(re, "timed_out"));
    const failure_kind = try requiredStr(get(re, "failure_kind"));
    if (!inSet(status, &mutation_runner_statuses)) return error.AiReportNotFound;
    if (!inSet(failure_kind, &runner_failure_kinds)) return error.AiReportNotFound;
    const stdout_excerpt = try requiredStr(get(re, "stdout_excerpt"));
    const stderr_excerpt = try requiredStr(get(re, "stderr_excerpt"));
    const failure_summary = try requiredStr(get(re, "failure_summary"));
    const exit_code_value = get(re, "exit_code") orelse return error.AiReportNotFound;
    if (get(re, "skip_reason") == null) return error.AiReportNotFound;
    return RunnerEvidence{
        .status = status,
        .command = cmd,
        .exit_code = switch (exit_code_value) {
            .integer => |n| n,
            .null => null,
            else => return error.AiReportNotFound,
        },
        .timed_out = timed_out,
        .failure_kind = failure_kind,
        .stdout_excerpt = try context.redactAndCapLogged(arena, stdout_excerpt, patterns, context.excerpt_limit, log),
        .stderr_excerpt = try context.redactAndCapLogged(arena, stderr_excerpt, patterns, context.excerpt_limit, log),
        .failure_summary = try context.redactAndCapLogged(arena, failure_summary, patterns, context.excerpt_limit, log),
        .skip_reason = if (optStr(present(get(re, "skip_reason")))) |sr| try context.redactField(arena, sr, patterns, log) else null,
    };
}

fn survivorMeta(case: std.json.Value) command.Failure!DoctestMeta {
    return .{
        .id = optStr(get(case, "id")),
        .file = s(get(case, "file")),
        .line_start = try optU32(get(case, "line_start")),
        .line_end = try optU32(get(case, "line_end")),
        .source_ref = optStr(get(case, "source_ref")),
        .block_refs = &.{},
        .kind = "mutation",
        .status = "survived",
    };
}

const SurvivorContextT = struct {
    schema_version: []const u8 = "zentinel.ai.doctest.context.v1",
    flow: []const u8 = "explain_doctest_survivor",
    created_by: []const u8 = "zentinel",
    provider_mode: []const u8,
    project: Project,
    doctest: DoctestMeta,
    evidence: SurvivorEvidence,
    privacy: Privacy,
};

/// Build the survivor context as a validated JSON value from a survived case.
pub fn buildSurvivorContextValue(arena: std.mem.Allocator, mode: Mode, case: std.json.Value, settings: Settings) !std.json.Value {
    const patterns = settings.redact_patterns;
    var log = context.RedactionLog.init(arena);
    const mutation = present(get(case, "mutation")) orelse return error.DoctestSurvivorNotFound;
    // Every report-sourced id/operator string under an untrusted --input-report is
    // routed through the same path-normalize + secret-scrub pass as .file/.source_ref,
    // so a path or secret smuggled in survivor_ref / doctest_case_id / case_id /
    // mutant_id / operator (whose validator prefix checks leave the suffix free) cannot
    // reach the provider, and redactions_applied stays truthful (mirroring the
    // same guard in the mutation AI flows).
    const ev = SurvivorEvidence{
        .survivor_ref = try context.redactField(arena, s(get(mutation, "survivor_ref")), patterns, &log),
        .source_case = .{
            .doctest_case_id = if (optStr(get(mutation, "doctest_case_id"))) |id| try context.redactField(arena, id, patterns, &log) else null,
            .file = try context.redactField(arena, s(get(case, "file")), patterns, &log),
            .source_ref = if (optStr(get(case, "source_ref"))) |sr| try context.redactField(arena, sr, patterns, &log) else null,
        },
        .mutation_case = .{
            .case_id = try context.redactField(arena, s(get(case, "id")), patterns, &log),
            .mutant_id = try context.redactField(arena, s(get(mutation, "mutant_id")), patterns, &log),
            .operator = try context.redactField(arena, s(get(mutation, "operator")), patterns, &log),
            // The mutated diff is source the AI is meant to see; path-normalize and
            // secret-scrub it (F-4) without redacting the code itself.
            .mutated_diff = try context.redactStrArray(arena, try readStrArray(arena, get(mutation, "mutated_diff")), patterns, &log),
            .backend_stability = "stable",
            .runner_evidence = try readRunnerEvidence(arena, mutation, patterns, &log),
        },
    };
    const meta = try redactedMeta(arena, try survivorMeta(case), patterns, &log);
    const ctx = SurvivorContextT{
        .provider_mode = provider.modeName(mode),
        .project = try projectOf(arena, settings, null, patterns, &log),
        .doctest = meta,
        .evidence = ev,
        .privacy = privacyOf(settings, &log),
    };
    const bytes = try std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
    return std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
}

/// Structural validator for the survivor `zentinel.ai.doctest.context.v1` value.
pub fn validateSurvivorContext(value: std.json.Value) ContextViolation {
    const obj = objOf(value) orelse return .not_object;
    if (!requireKeys(obj, &.{ "schema_version", "flow", "created_by", "provider_mode", "project", "doctest", "evidence", "privacy" })) return .missing_field;
    if (!enumOk(obj, "schema_version", &.{"zentinel.ai.doctest.context.v1"})) return .bad_enum;
    if (!enumOk(obj, "flow", &.{"explain_doctest_survivor"})) return .bad_enum;
    if (!enumOk(obj, "created_by", &.{"zentinel"})) return .bad_enum;
    if (!enumOk(obj, "provider_mode", &.{ "disabled", "stub", "local", "remote" })) return .bad_enum;

    const doctest = objOf(obj.get("doctest").?) orelse return .not_object;
    if (!requireKeys(doctest, &.{ "id", "file", "line_start", "line_end", "source_ref", "block_refs", "kind", "status" })) return .missing_field;
    if (!enumOk(doctest, "kind", &.{"mutation"})) return .bad_enum;
    if (!enumOk(doctest, "status", &.{"survived"})) return .bad_enum;

    const ev = objOf(obj.get("evidence").?) orelse return .not_object;
    if (!enumOk(ev, "kind", &.{"doctest_survivor"})) return .bad_evidence;
    if (!requireKeys(ev, &.{ "kind", "survivor_ref", "source_case", "mutation_case" })) return .bad_evidence;
    if (!std.mem.startsWith(u8, s(ev.get("survivor_ref")), "ds_")) return .bad_evidence;
    const sc = objOf(ev.get("source_case").?) orelse return .bad_evidence;
    if (!requireKeys(sc, &.{ "doctest_case_id", "file", "source_ref" })) return .bad_evidence;
    const mc = objOf(ev.get("mutation_case").?) orelse return .bad_evidence;
    if (!requireKeys(mc, &.{ "case_id", "mutant_id", "operator", "mutated_diff", "backend_stability", "runner_evidence" })) return .bad_evidence;
    if (!std.mem.startsWith(u8, s(mc.get("case_id")), "dm_")) return .bad_evidence;
    if (!std.mem.startsWith(u8, s(mc.get("mutant_id")), "m_")) return .bad_evidence;
    const re = objOf(mc.get("runner_evidence").?) orelse return .bad_evidence;
    if (!requireKeys(re, &.{ "status", "command", "exit_code", "timed_out", "failure_kind", "stdout_excerpt", "stderr_excerpt", "failure_summary", "skip_reason" })) return .bad_evidence;
    if (!enumOk(re, "status", &mutation_runner_statuses)) return .bad_evidence;
    if (!enumOk(re, "failure_kind", &runner_failure_kinds)) return .bad_evidence;
    const cmd = objOf(re.get("command").?) orelse return .bad_evidence;
    if (!requireKeys(cmd, &.{ "original", "argv", "cwd", "environment_policy", "shell" })) return .bad_evidence;
    if (!enumOk(cmd, "environment_policy", &.{"minimal"})) return .bad_evidence;
    switch (cmd.get("shell").?) {
        .bool => |shell| if (shell) return .bad_evidence,
        else => return .bad_evidence,
    }

    const project = objOf(obj.get("project").?) orelse return .not_object;
    if (!requireKeys(project, &.{ "name", "root_label", "zig_version", "zentinel_version" })) return .missing_field;
    const privacy = objOf(obj.get("privacy").?) orelse return .not_object;
    if (!requireKeys(privacy, &.{ "remote_allowed", "source_context_policy", "redactions_applied" })) return .missing_field;
    return .ok;
}

pub fn buildSurvivorPromptValue(arena: std.mem.Allocator, ctx: std.json.Value) !std.json.Value {
    const prompt = Prompt{
        .flow = "explain_doctest_survivor",
        .instructions = &prompt_instructions,
        .context = ctx,
        .response_schema = .{ .name = "zentinel.ai.explain.response.v1" },
    };
    const bytes = try std.json.Stringify.valueAlloc(arena, prompt, .{ .whitespace = .indent_2 });
    return std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
}

/// Validate the survivor prompt envelope.
pub fn validateSurvivorPrompt(value: std.json.Value) PromptViolation {
    const obj = objOf(value) orelse return .not_object;
    if (!requireKeys(obj, &.{ "schema_version", "flow", "instructions", "context", "response_schema" })) return .missing_field;
    if (!eqStr(s(obj.get("schema_version")), "zentinel.ai.prompt.v1")) return .bad_schema_version;
    if (!eqStr(s(obj.get("flow")), "explain_doctest_survivor")) return .bad_flow;
    const instr = arr(obj.get("instructions")) orelse return .no_instructions;
    if (instr.len == 0) return .no_instructions;
    const ctx = obj.get("context").?;
    const ctx_obj = objOf(ctx) orelse return .bad_context;
    if (!eqStr(s(ctx_obj.get("schema_version")), "zentinel.ai.doctest.context.v1")) return .unknown_context_schema;
    if (validateSurvivorContext(ctx) != .ok) return .bad_context;
    const rs = objOf(obj.get("response_schema").?) orelse return .bad_response_schema;
    if (!eqStr(s(rs.get("name")), "zentinel.ai.explain.response.v1")) return .bad_response_schema;
    return .ok;
}

fn stubSurvivorExplain(arena: std.mem.Allocator, case: std.json.Value, patterns: []const []const u8) redaction.Error!Response {
    const mutation = get(case, "mutation");
    // The report is untrusted: redact every field echoed into the rendered
    // advisory (summary + evidence refs) so a path- or secret-shaped survivor_ref/
    // id/operator cannot leak to stdout, matching stubExplain/stubSuggest (F-4).
    var sink = context.RedactionLog.init(arena);
    const survivor_ref = try context.redactField(arena, s(getO(mutation, "survivor_ref")), patterns, &sink);
    const dm = try context.redactField(arena, s(get(case, "id")), patterns, &sink);
    const operator = try context.redactField(arena, s(getO(mutation, "operator")), patterns, &sink);
    const refs = try arena.alloc(EvidenceRef, 2);
    refs[0] = .{ .kind = "doctest_survivor", .ref = survivor_ref };
    refs[1] = .{ .kind = "mutation_case", .ref = dm };
    return .{ .explain = .{
        .classification = "doctest_survivor_missing_assertion",
        .confidence = "medium",
        .summary = try std.fmt.allocPrint(arena, "Documentation mutant {s} ({s}) survived: the example does not assert the mutated behavior. Survivor ref {s}.", .{ dm, operator, survivor_ref }),
        .evidence_refs = refs,
        .next_action = "Strengthen the documentation example to assert the mutated behavior, then re-run zentinel doctest --mutate; do not mark the survivor equivalent, killed, or skipped without human review.",
    } };
}

pub const SurvivorInput = struct {
    survivor_ref: ?[]const u8,
    provider_override: ?Mode,
    report_json: ?[]const u8,
    settings: Settings,
};

/// Advisory survivor explanation. Reads the deterministic mutation-aware doctest
/// report, resolves the `ds_` survivor ref, builds + validates the context and
/// prompt, runs the deterministic stub, validates the explain response, and
/// renders it. Never writes a report, status, snapshot, or documentation.
pub fn runSurvivor(arena: std.mem.Allocator, input: SurvivorInput, format: Format) RunError!Outcome {
    const mode = try command.resolveMode(input.settings, input.provider_override);
    const bytes = input.report_json orelse return error.AiReportNotFound;
    const report = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch return error.AiReportNotFound;
    if (objOf(report) == null or get(report, "cases") == null) return error.AiReportNotFound;
    const ref = input.survivor_ref orelse return error.DoctestSurvivorNotFound;
    const case = resolveSurvivor(report, ref) orelse return error.DoctestSurvivorNotFound;

    const ctx = buildSurvivorContextValue(arena, mode, case, input.settings) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        // An out-of-range or non-integer report integer is an invalid report.
        error.AiReportNotFound => return error.AiReportNotFound,
        else => return error.AiResponseInvalid,
    };
    if (validateSurvivorContext(ctx) != .ok) return error.AiResponseInvalid;
    const prompt = buildSurvivorPromptValue(arena, ctx) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.AiResponseInvalid,
    };
    if (validateSurvivorPrompt(prompt) != .ok) return error.AiResponseInvalid;

    const response = stubSurvivorExplain(arena, case, input.settings.redact_patterns) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        error.RedactionFailed => return error.AiResponseInvalid,
    };
    const json = try responseJson(arena, response);
    const value = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch return error.AiResponseInvalid;
    if (command.validateResponse(.explain, value) != .ok) return error.AiResponseInvalid;

    const body = switch (format) {
        .json => json,
        .text => try renderText(arena, response),
    };
    return .{ .exit_code = 0, .body = body, .format = format };
}
