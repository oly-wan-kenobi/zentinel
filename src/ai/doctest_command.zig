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
// deferred `explain_doctest_survivor` flow (task 067) and `doctest_survivor`
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

pub fn responseSchemaName(flow: Flow) []const u8 {
    return switch (flow) {
        .explain_doctest_failure => "zentinel.ai.explain.response.v1",
        .suggest_doctest, .suggest_missing_doctests => "zentinel.ai.doctest.suggest.response.v1",
        .review_snapshot => "zentinel.ai.doctest.snapshot_review.response.v1",
    };
}

/// AI-only and doctest-only command failures. The AI failures are shared with the
/// mutation engine; the two doctest failures carry their documented codes.
pub const Failure = command.Failure || error{ DoctestCaseNotFound, DoctestDocNotFound };
pub const RunError = Failure || error{OutOfMemory};

pub fn failureToken(err: Failure) []const u8 {
    return switch (err) {
        error.DoctestCaseNotFound => "ZNTL_DOCTEST_CASE_NOT_FOUND",
        error.DoctestDocNotFound => "ZNTL_DOCTEST_DOC_NOT_FOUND",
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
fn optU32(v: ?std.json.Value) ?u32 {
    if (v) |x| return switch (x) {
        .integer => |n| if (n >= 0) @intCast(n) else null,
        else => null,
    };
    return null;
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

fn projectOf(settings: Settings, report: ?std.json.Value) Project {
    const run_info = if (report) |r| get(r, "run") else null;
    return .{
        .name = settings.project_name,
        .root_label = "<project>",
        .zig_version = sOr(getO(run_info, "zig_version"), settings.zig_version),
        .zentinel_version = sOr(getO(run_info, "zentinel_version"), settings.zentinel_version),
    };
}
fn privacyOf(settings: Settings) Privacy {
    return .{ .remote_allowed = settings.remote_allowed, .source_context_policy = "minimal", .redactions_applied = &.{} };
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
fn readCommand(arena: std.mem.Allocator, v: ?std.json.Value) !?CommandEv {
    const o = v orelse return null;
    if (objOf(o) == null) return null;
    return CommandEv{
        .original = s(get(o, "original")),
        .argv = try readStrArray(arena, get(o, "argv")),
        .cwd = sOr(get(o, "cwd"), "<project>"),
    };
}
fn readDiagnostics(arena: std.mem.Allocator, case: std.json.Value) ![]const Diagnostic {
    const items = arr(get(case, "diagnostics")) orelse return &.{};
    const buf = try arena.alloc(Diagnostic, items.len);
    for (items, 0..) |it, idx| buf[idx] = .{
        .code = s(get(it, "code")),
        .message = s(get(it, "message")),
        .file = optStr(get(it, "file")),
        .line = optU32(get(it, "line")),
        .column = optU32(get(it, "column")),
    };
    return buf;
}
fn redactOpt(arena: std.mem.Allocator, v: ?std.json.Value, patterns: []const []const u8) redaction.Error!?[]const u8 {
    const t = optStr(v) orelse return null;
    return try context.redactAndCap(arena, t, patterns, context.excerpt_limit);
}

fn metaFromCase(case: std.json.Value) DoctestMeta {
    return .{
        .id = optStr(get(case, "id")),
        .file = s(get(case, "file")),
        .line_start = optU32(get(case, "line_start")),
        .line_end = optU32(get(case, "line_end")),
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
    const bytes = switch (flow) {
        .explain_doctest_failure => blk: {
            const case = input.case orelse return error.DoctestCaseNotFound;
            const result = get(case, "result");
            const snapshot = getO(result, "snapshot");
            const command_ev = try readCommand(arena, get(case, "command"));
            const ev = CaseFailureEvidence{
                .status = sOr(get(case, "status"), "failed"),
                .command = command_ev,
                .expected_excerpt = try redactOpt(arena, getO(snapshot, "expected_excerpt"), patterns),
                .actual_excerpt = try redactOpt(arena, getO(snapshot, "actual_excerpt"), patterns),
                .normalized_expected_excerpt = try redactOpt(arena, getO(snapshot, "normalized_expected_excerpt"), patterns),
                .normalized_actual_excerpt = try redactOpt(arena, getO(snapshot, "normalized_actual_excerpt"), patterns),
                .diagnostics = try readDiagnostics(arena, case),
                .failure_summary = try context.redactAndCap(arena, s(getO(result, "failure_summary")), patterns, context.excerpt_limit),
            };
            const ctx = DoctestContext(CaseFailureEvidence){
                .flow = flowName(flow),
                .provider_mode = provider_mode,
                .project = projectOf(settings, input.report),
                .doctest = metaFromCase(case),
                .evidence = ev,
                .privacy = privacyOf(settings),
            };
            break :blk try std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
        },
        .review_snapshot => blk: {
            const case = input.case orelse return error.DoctestCaseNotFound;
            const snap = present(getO(get(case, "result"), "snapshot")) orelse return error.DoctestCaseNotFound;
            const ev = SnapshotDiffEvidence{
                .case_status = sOr(get(case, "status"), "failed"),
                .snapshot = .{
                    .expected_excerpt = try context.redactAndCap(arena, s(get(snap, "expected_excerpt")), patterns, context.excerpt_limit),
                    .actual_excerpt = try context.redactAndCap(arena, s(get(snap, "actual_excerpt")), patterns, context.excerpt_limit),
                    .normalized_expected_excerpt = try context.redactAndCap(arena, s(get(snap, "normalized_expected_excerpt")), patterns, context.excerpt_limit),
                    .normalized_actual_excerpt = try context.redactAndCap(arena, s(get(snap, "normalized_actual_excerpt")), patterns, context.excerpt_limit),
                    .match_mode = sOr(get(snap, "match_mode"), "exact"),
                    .expected_block_ref = optStr(get(snap, "expected_block_ref")),
                    .actual_ref = sOr(get(snap, "actual_ref"), "stdout"),
                    .matched = switch (get(snap, "matched") orelse std.json.Value{ .bool = false }) {
                        .bool => |b| b,
                        else => false,
                    },
                },
            };
            const ctx = DoctestContext(SnapshotDiffEvidence){
                .flow = flowName(flow),
                .provider_mode = provider_mode,
                .project = projectOf(settings, input.report),
                .doctest = metaFromCase(case),
                .evidence = ev,
                .privacy = privacyOf(settings),
            };
            break :blk try std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
        },
        .suggest_doctest => blk: {
            const doc = input.doc_path orelse return error.DoctestDocNotFound;
            const ev = DocsTargetEvidence{
                .target_file = doc,
                .heading_context = &.{},
                .docs_metadata = .{ .public = isPublicDoc(doc), .has_doctests = false, .executable_case_count = 0, .nearest_heading = null },
                .report_summary = null,
            };
            const ctx = DoctestContext(DocsTargetEvidence){
                .flow = flowName(flow),
                .provider_mode = provider_mode,
                .project = projectOf(settings, input.report),
                .doctest = docsTargetMeta(doc),
                .evidence = ev,
                .privacy = privacyOf(settings),
            };
            break :blk try std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
        },
        .suggest_missing_doctests => blk: {
            const doc = input.doc_path orelse "docs/";
            const docs = try arena.alloc(DocsEntry, 1);
            docs[0] = .{ .file = doc, .public = isPublicDoc(doc), .has_doctests = false, .executable_case_count = 0 };
            const candidates = try arena.alloc(Candidate, 1);
            candidates[0] = .{ .file = doc, .heading = "", .line_hint = null, .reason = "Public docs path lacks an executable doctest block.", .missing_kind = missingKindFor(doc) };
            const ev = MissingEvidence{ .docs = docs, .candidates = candidates };
            const ctx = DoctestContext(MissingEvidence){
                .flow = flowName(flow),
                .provider_mode = provider_mode,
                .project = projectOf(settings, input.report),
                .doctest = docsTargetMeta(doc),
                .evidence = ev,
                .privacy = privacyOf(settings),
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
/// survivor flow (task 067) and a `doctest_survivor` evidence kind.
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

fn stubExplain(arena: std.mem.Allocator, case: std.json.Value) !Response {
    const status = s(get(case, "status"));
    const classification = explainClassification(status);
    const id = s(get(case, "id"));
    const file = s(get(case, "file"));
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

fn stubSuggest(arena: std.mem.Allocator, doc_path: []const u8) !Response {
    const suggestions = try arena.alloc(Suggestion, 1);
    suggestions[0] = .{
        .target_file = doc_path,
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

fn stubSnapshotReview(arena: std.mem.Allocator, case: std.json.Value) !Response {
    const snap = getO(get(case, "result"), "snapshot");
    const expected = s(getO(snap, "normalized_expected_excerpt"));
    const actual = s(getO(snap, "normalized_actual_excerpt"));
    const classification = snapshotClassification(expected, actual);
    const risk: []const u8 = if (eqStr(classification, "semantic_change")) "high" else if (eqStr(classification, "wording_change")) "medium" else "low";
    const block_ref = optStr(getO(snap, "expected_block_ref")) orelse s(get(case, "source_ref"));
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
                (stubExplain(arena, case) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
                })
            else
                (stubSnapshotReview(arena, case) catch |e| switch (e) {
                    error.OutOfMemory => return error.OutOfMemory,
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
            break :blk stubSuggest(arena, doc) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
            };
        },
        .suggest_missing_doctests => blk: {
            if (input.doc_path) |d| {
                if (!input.doc_exists) return error.DoctestDocNotFound;
                ctx_input = .{ .doc_path = d };
            }
            break :blk stubSuggest(arena, input.doc_path orelse "docs/") catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
            };
        },
    };

    // Build, validate the doctest context and prompt envelope before "sending".
    const ctx = buildContextValue(arena, input.flow, mode, ctx_input, input.settings) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
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
