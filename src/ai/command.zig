// Layer: deterministic_core
//
// Advisory AI command engine (docs/AI_PROMPT_CONTRACTS.md, docs/CLI_SPEC.md).
// Owns the deterministic plumbing behind `zentinel explain`, `zentinel suggest`,
// and `zentinel review-tests`: provider resolution from config + CLI override,
// read-only mutation-report parsing, durable/display mutant-ref resolution scoped
// to the selected report, construction of the `zentinel.ai.prompt.v1` request
// envelope (embedding a validated `zentinel.ai.context.v1` payload), a
// deterministic stub provider, response-schema validation with safety checks, and
// text/JSON rendering. The AI surface is advisory only: nothing here ever sets a
// mutant status, a report status, or any deterministic result field. The provider
// receives only the redacted, bounded context; malformed or unsafe model output is
// rejected deterministically and never alters a report.
const std = @import("std");
const context = @import("context.zig");
const provider = @import("provider.zig");
const redaction = @import("redaction.zig");

pub const Mode = provider.Mode;

/// Default mutation-AI report path when `--input-report` is omitted (docs/CLI_SPEC.md).
pub const default_report_path = "zig-out/zentinel/report.json";

/// Default redaction patterns mirrored from config (docs/CONFIG_SPEC.md). Used by
/// the CLI adapter when no config file is present.
pub const default_redact_patterns = [_][]const u8{ "(?i)api[_-]?key", "(?i)token" };

/// Mandatory prompt-safety instructions (docs/AI_PROMPT_CONTRACTS.md, Prompt Safety).
const prompt_instructions = [_][]const u8{
    "Use only provided context.",
    "Do not infer unavailable source.",
    "Do not decide whether the mutant is equivalent.",
    "Return JSON only.",
};

pub const Flow = enum { explain, suggest, review_tests };

pub fn flowName(flow: Flow) []const u8 {
    return switch (flow) {
        .explain => "explain",
        .suggest => "suggest",
        .review_tests => "review_tests",
    };
}

pub fn responseSchemaName(flow: Flow) []const u8 {
    return switch (flow) {
        .explain => "zentinel.ai.explain.response.v1",
        .suggest => "zentinel.ai.suggest.response.v1",
        .review_tests => "zentinel.ai.review_tests.response.v1",
    };
}

fn parseFlow(name: []const u8) ?Flow {
    if (eqStr(name, "explain")) return .explain;
    if (eqStr(name, "suggest")) return .suggest;
    if (eqStr(name, "review_tests")) return .review_tests;
    return null;
}

/// AI-only command failures. These never fail a deterministic mutation run; the
/// CLI adapter maps each to its documented `ZNTL_AI_*` code (docs/FAILURE_MODES.md).
pub const Failure = error{
    AiDisabled,
    AiProviderNotAllowed,
    AiReportNotFound,
    AiTargetNotFound,
    AiResponseInvalid,
};

pub const RunError = Failure || error{OutOfMemory};

pub fn failureToken(err: Failure) []const u8 {
    return switch (err) {
        error.AiDisabled => "ZNTL_AI_DISABLED",
        error.AiProviderNotAllowed => "ZNTL_AI_PROVIDER_NOT_ALLOWED",
        error.AiReportNotFound => "ZNTL_AI_REPORT_NOT_FOUND",
        error.AiTargetNotFound => "ZNTL_AI_TARGET_NOT_FOUND",
        error.AiResponseInvalid => "ZNTL_AI_RESPONSE_INVALID",
    };
}

/// AI-only failures are usage/advisory failures; deterministic reports are never
/// affected, so they share the CLI usage exit code.
pub fn failureExit(err: Failure) u8 {
    return switch (err) {
        error.AiDisabled,
        error.AiProviderNotAllowed,
        error.AiReportNotFound,
        error.AiTargetNotFound,
        error.AiResponseInvalid,
        => 2,
    };
}

pub const Settings = struct {
    ai_enabled: bool,
    config_mode: Mode,
    remote_allowed: bool,
    redact_patterns: []const []const u8 = &.{},
    project_name: []const u8 = "zentinel",
    zig_version: []const u8 = "0.16.0",
    zentinel_version: []const u8 = "0.0.0",
};

/// Resolve the effective provider mode from normalized config plus an optional
/// command-local `--ai-provider` override. An override is explicit opt-in for the
/// invocation; with no override the mode comes from config when AI is enabled and
/// is `disabled` otherwise. `disabled` is a deterministic AI-disabled failure;
/// `remote` requires `remote_allowed`.
pub fn resolveMode(settings: Settings, override: ?Mode) Failure!Mode {
    const effective: Mode = override orelse (if (settings.ai_enabled) settings.config_mode else .disabled);
    switch (effective) {
        .disabled => return error.AiDisabled,
        .remote => {
            if (!settings.remote_allowed) return error.AiProviderNotAllowed;
            return .remote;
        },
        .stub, .local => return effective,
    }
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
fn i64v(v: ?std.json.Value) i64 {
    if (v) |x| return switch (x) {
        .integer => |n| n,
        else => 0,
    };
    return 0;
}

fn boolOr(v: ?std.json.Value, default: bool) bool {
    if (v) |x| return switch (x) {
        .bool => |b| b,
        else => default,
    };
    return default;
}

fn optString(v: ?std.json.Value) ?[]const u8 {
    if (v) |x| return switch (x) {
        .string => |t| t,
        else => null,
    };
    return null;
}

fn optI64(v: ?std.json.Value) ?i64 {
    if (v) |x| return switch (x) {
        .integer => |n| n,
        else => null,
    };
    return null;
}

/// Narrow a report-sourced JSON integer to u32 for an AI context field. The
/// report is untrusted (`--input-report`), so an out-of-range or non-integer
/// value must become a clean invalid-report failure rather than a panicking
/// `@intCast` (abort in Debug/ReleaseSafe) or a silent wrap (ReleaseFast). An
/// absent or null field defaults to 0; a negative integer clamps to 0 (a report
/// line/column/display id has no negative meaning); a present non-integer or a
/// value above maxInt(u32) is rejected as an invalid report.
fn reportU32(v: ?std.json.Value) Failure!u32 {
    const x = v orelse return 0;
    switch (x) {
        .null => return 0,
        .integer => |n| {
            if (n < 0) return 0;
            if (n > std.math.maxInt(u32)) return error.AiReportNotFound;
            return @intCast(n);
        },
        else => return error.AiReportNotFound,
    }
}
fn arrOf(v: ?std.json.Value) ?[]std.json.Value {
    if (v) |x| return switch (x) {
        .array => |a| a.items,
        else => null,
    };
    return null;
}

// --- Mutant reference resolution -------------------------------------------

/// Resolve `<mutant-ref>` against the selected report only. A `m_`-prefixed ref
/// matches a durable id; any other ref is parsed as a report-local display id.
/// Display ids are scoped to this report, so an id from another report simply does
/// not resolve.
pub fn resolveMutant(report: std.json.Value, ref: []const u8) ?std.json.Value {
    const mutants = arrOf(get(report, "mutants")) orelse return null;
    if (std.mem.startsWith(u8, ref, "m_")) {
        for (mutants) |m| if (eqStr(s(get(m, "id")), ref)) return m;
        return null;
    }
    const want = std.fmt.parseInt(i64, ref, 10) catch return null;
    for (mutants) |m| if (i64v(get(m, "display_id")) == want) return m;
    return null;
}

fn firstSurvivor(report: std.json.Value) ?std.json.Value {
    const mutants = arrOf(get(report, "mutants")) orelse return null;
    for (mutants) |m| if (eqStr(s(getO(get(m, "result"), "status")), "survived")) return m;
    return null;
}

// --- Prompt request envelope -----------------------------------------------

const ResponseSchemaRef = struct { name: []const u8 };

const Prompt = struct {
    schema_version: []const u8 = "zentinel.ai.prompt.v1",
    flow: []const u8,
    instructions: []const []const u8,
    context: context.Context,
    response_schema: ResponseSchemaRef,
};

fn readSpan(v: ?std.json.Value) Failure!context.Span {
    return .{
        // byte_start/byte_end are u64: any non-negative i64 fits, so the existing
        // clamp cannot panic or wrap. The narrowed u32 line/column fields are
        // bounds-checked because an out-of-range report value would otherwise
        // panic the @intCast (task 107).
        .byte_start = @intCast(@max(0, i64v(getO(v, "byte_start")))),
        .byte_end = @intCast(@max(0, i64v(getO(v, "byte_end")))),
        .line_start = try reportU32(getO(v, "line_start")),
        .column_start = try reportU32(getO(v, "column_start")),
        .line_end = try reportU32(getO(v, "line_end")),
        .column_end = try reportU32(getO(v, "column_end")),
    };
}

fn readStrArray(arena: std.mem.Allocator, v: ?std.json.Value) ![]const []const u8 {
    const items = arrOf(v) orelse return &.{};
    const buf = try arena.alloc([]const u8, items.len);
    for (items, 0..) |it, idx| buf[idx] = switch (it) {
        .string => |t| t,
        else => "",
    };
    return buf;
}

fn redactedEvidence(arena: std.mem.Allocator, ev: ?std.json.Value, patterns: []const []const u8, log: *context.RedactionLog) redaction.Error!context.Evidence {
    return .{
        .stdout_excerpt = try context.redactAndCapLogged(arena, s(getO(ev, "stdout_excerpt")), patterns, context.excerpt_limit, log),
        .stderr_excerpt = try context.redactAndCapLogged(arena, s(getO(ev, "stderr_excerpt")), patterns, context.excerpt_limit, log),
        .failure_summary = try context.redactAndCapLogged(arena, s(getO(ev, "failure_summary")), patterns, context.excerpt_limit, log),
    };
}

fn redactedArgv(arena: std.mem.Allocator, argv_value: ?std.json.Value, patterns: []const []const u8, log: *context.RedactionLog) redaction.Error![]const []const u8 {
    const argv = arrOf(argv_value) orelse return arena.dupe([]const u8, &.{ "zig", "build", "test" });
    const out = try arena.alloc([]const u8, argv.len);
    for (argv, 0..) |arg, i| {
        out[i] = try context.redactField(arena, switch (arg) {
            .string => |t| t,
            else => "",
        }, patterns, log);
    }
    return out;
}

fn commandResultFromReport(
    arena: std.mem.Allocator,
    value: std.json.Value,
    patterns: []const []const u8,
    log: *context.RedactionLog,
    default_status: []const u8,
    default_failure_kind: []const u8,
) redaction.Error!context.CommandResult {
    const cmd = get(value, "command");
    const original = try context.redactField(arena, sOr(getO(cmd, "original"), "zig build test"), patterns, log);
    const argv = try redactedArgv(arena, getO(cmd, "argv"), patterns, log);
    const cwd = try context.redactField(arena, sOr(getO(cmd, "cwd"), "<project>"), patterns, log);
    return .{
        .command = .{
            .original = original,
            .argv = argv,
            .cwd = cwd,
            .environment_policy = sOr(getO(cmd, "environment_policy"), "minimal"),
            .shell = boolOr(getO(cmd, "shell"), false),
        },
        .phase = sOr(get(value, "phase"), "mutant"),
        .status = sOr(get(value, "status"), default_status),
        .exit_code = optI64(get(value, "exit_code")),
        .timed_out = boolOr(get(value, "timed_out"), false),
        .failure_kind = sOr(get(value, "failure_kind"), default_failure_kind),
        .duration_ms_normalized = "<duration>",
        .evidence = try redactedEvidence(arena, get(value, "evidence"), patterns, log),
        .skip_reason = optString(get(value, "skip_reason")),
    };
}

fn commandsFromResult(
    arena: std.mem.Allocator,
    result: std.json.Value,
    result_evidence: context.Evidence,
    patterns: []const []const u8,
    log: *context.RedactionLog,
    default_status: []const u8,
    default_failure_kind: []const u8,
) redaction.Error![]const context.CommandResult {
    if (arrOf(get(result, "commands"))) |items| {
        if (items.len > 0) {
            const out = try arena.alloc(context.CommandResult, items.len);
            for (items, 0..) |item, i| {
                out[i] = try commandResultFromReport(arena, item, patterns, log, default_status, default_failure_kind);
            }
            return out;
        }
    }
    const fallback = context.CommandResult{
        .command = .{
            .original = "zig build test",
            .argv = &.{ "zig", "build", "test" },
            .cwd = "<project>",
            .environment_policy = "minimal",
            .shell = false,
        },
        .phase = "mutant",
        .status = default_status,
        .exit_code = exitCodeFor(s(get(result, "status"))),
        .timed_out = false,
        .failure_kind = default_failure_kind,
        .duration_ms_normalized = "<duration>",
        .evidence = result_evidence,
        .skip_reason = if (eqStr(default_status, "skipped")) sOr(get(result, "skip_reason"), "command skipped") else null,
    };
    const out = try arena.alloc(context.CommandResult, 1);
    out[0] = fallback;
    return out;
}

fn commandStatusFor(status: []const u8) []const u8 {
    if (eqStr(status, "survived")) return "passed";
    if (eqStr(status, "skipped")) return "skipped";
    if (eqStr(status, "compiler_crash")) return "compiler_crash";
    if (eqStr(status, "timeout")) return "timeout";
    return "failed";
}
fn failureKindFor(status: []const u8) []const u8 {
    if (eqStr(status, "survived")) return "none";
    if (eqStr(status, "compile_error")) return "compile_error";
    if (eqStr(status, "compiler_crash")) return "compiler_crash";
    if (eqStr(status, "timeout")) return "timeout";
    if (eqStr(status, "skipped")) return "skipped";
    return "test_failure";
}
fn exitCodeFor(status: []const u8) ?i64 {
    if (eqStr(status, "survived")) return 0;
    if (eqStr(status, "skipped")) return null;
    return 1;
}
fn baselineStatusFor(report: std.json.Value) []const u8 {
    const st = s(getO(get(report, "baseline"), "status"));
    if (eqStr(st, "passed")) return "passed";
    if (eqStr(st, "failed")) return "failed";
    return "unknown";
}
fn categoryForOperator(operator: []const u8) []const u8 {
    if (contains(operator, "comparison") or contains(operator, "boundary")) return "boundary";
    if (contains(operator, "optional") or contains(operator, "null")) return "optional";
    if (contains(operator, "errdefer") or contains(operator, "cleanup")) return "cleanup";
    if (contains(operator, "error")) return "error";
    if (contains(operator, "logical") or contains(operator, "boolean")) return "logical";
    if (contains(operator, "comptime")) return "comptime";
    if (contains(operator, "arithmetic")) return "arithmetic";
    if (contains(operator, "literal") or contains(operator, "constant")) return "constant";
    return "other";
}
fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

fn buildContext(
    arena: std.mem.Allocator,
    flow: Flow,
    mode: Mode,
    mutant: std.json.Value,
    report: std.json.Value,
    settings: Settings,
) (Failure || redaction.Error)!context.Context {
    const result = get(mutant, "result") orelse return error.RedactionFailed;
    const rstatus = s(get(result, "status"));
    const patterns = settings.redact_patterns;
    var log = context.RedactionLog.init(arena);

    // Redact every path/source/diff-bearing field through the same path-normalize
    // + secret-scrub pass as evidence, accumulating what was redacted so
    // privacy.redactions_applied stays truthful (audit F-4). These must be
    // computed before the context literal because redactions_applied appears
    // earlier in the struct and must reflect every field's redactions.
    const result_evidence = try redactedEvidence(arena, get(result, "evidence"), patterns, &log);
    const m_file = try context.redactField(arena, s(get(mutant, "file")), patterns, &log);
    const m_original = try context.redactField(arena, s(get(mutant, "original")), patterns, &log);
    const m_replacement = try context.redactField(arena, s(get(mutant, "replacement")), patterns, &log);
    const m_diff = try context.redactStrArray(arena, try readStrArray(arena, get(mutant, "diff")), patterns, &log);

    const cmd_status = commandStatusFor(rstatus);
    const cmd_failure_kind = blk: {
        const cmds = arrOf(get(result, "commands"));
        if (cmds) |list| if (list.len > 0) {
            const fk = s(get(list[0], "failure_kind"));
            if (fk.len > 0) break :blk fk;
        };
        break :blk failureKindFor(rstatus);
    };
    const commands = try commandsFromResult(arena, result, result_evidence, patterns, &log, cmd_status, cmd_failure_kind);

    const run_info = get(report, "run");
    const selection = get(mutant, "test_selection");

    return context.Context{
        .schema_version = "zentinel.ai.context.v1",
        .flow = flowName(flow),
        .created_by = "zentinel",
        .provider_mode = provider.modeName(mode),
        .privacy = .{
            .redactions_applied = log.applied(),
            .source_context_policy = "none",
            .remote_allowed = settings.remote_allowed,
        },
        .project = .{
            .name = settings.project_name,
            .root_label = "<project>",
            .zig_version = sOr(getO(run_info, "zig_version"), settings.zig_version),
            .zentinel_version = sOr(getO(run_info, "zentinel_version"), settings.zentinel_version),
        },
        .mutant = .{
            .id = s(get(mutant, "id")),
            .display_id = try reportU32(get(mutant, "display_id")),
            .backend = sOr(get(mutant, "backend"), "ast"),
            .backend_stability = sOr(get(mutant, "backend_stability"), "stable"),
            .operator = s(get(mutant, "operator")),
            .operator_stability = sOr(get(mutant, "operator_stability"), "stable"),
            .file = m_file,
            .span = try readSpan(get(mutant, "span")),
            .original = m_original,
            .replacement = m_replacement,
            .diff = m_diff,
            .expected_compile = sOr(get(mutant, "expected_compile"), "compiles"),
        },
        .result = .{
            .status = rstatus,
            .mode = sOr(get(result, "mode"), "Debug"),
            .commands = commands,
            .phase = "mutant",
            .duration_ms_normalized = "<duration>",
            .evidence = result_evidence,
            .skip_reason = if (eqStr(rstatus, "skipped")) sOr(get(result, "skip_reason"), "result skipped") else null,
        },
        .source_context = .{
            .policy = "none",
            .language = "zig",
            .before_lines = 0,
            .after_lines = 0,
            .snippet = &.{},
            .symbols = &.{},
        },
        .test_context = .{
            .selection_reason = sOr(getO(selection, "strategy"), "same_file_then_package"),
            .selected_tests = &.{},
            .baseline_status = baselineStatusFor(report),
            .same_file_tests_excluded_from_mutation = true,
        },
        .operator = .{
            .name = s(get(mutant, "operator")),
            .category = categoryForOperator(s(get(mutant, "operator"))),
            .equivalent_risks = &.{},
            .suggested_test_focus = &.{},
        },
    };
}

/// Build the `zentinel.ai.prompt.v1` request envelope as a JSON value, embedding a
/// `zentinel.ai.context.v1` payload built from the resolved mutant. The value is
/// validated before it is sent to any provider.
pub fn buildPromptValue(
    arena: std.mem.Allocator,
    flow: Flow,
    mode: Mode,
    mutant: std.json.Value,
    report: std.json.Value,
    settings: Settings,
) !std.json.Value {
    const ctx = try buildContext(arena, flow, mode, mutant, report, settings);
    const prompt = Prompt{
        .flow = flowName(flow),
        .instructions = &prompt_instructions,
        .context = ctx,
        .response_schema = .{ .name = responseSchemaName(flow) },
    };
    const bytes = try std.json.Stringify.valueAlloc(arena, prompt, .{ .whitespace = .indent_2 });
    return std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
}

pub const PromptViolation = enum {
    ok,
    not_object,
    missing_field,
    bad_schema_version,
    bad_flow,
    no_instructions,
    bad_context,
    unknown_context_schema,
    bad_response_schema,
};

/// Structural gate for a prompt envelope. Mutation flows must embed a context
/// whose `schema_version` is `zentinel.ai.context.v1` and which validates against
/// the registered context schema; a schema-version-only placeholder fails as
/// `bad_context`, and any other context schema fails as `unknown_context_schema`.
pub fn validatePrompt(value: std.json.Value) PromptViolation {
    const obj = objOf(value) orelse return .not_object;
    for ([_][]const u8{ "schema_version", "flow", "instructions", "context", "response_schema" }) |k| {
        if (obj.get(k) == null) return .missing_field;
    }
    if (!eqStr(s(obj.get("schema_version")), "zentinel.ai.prompt.v1")) return .bad_schema_version;
    const flow_name = s(obj.get("flow"));
    const flow = parseFlow(flow_name) orelse return .bad_flow;
    const instr = arrOf(obj.get("instructions")) orelse return .no_instructions;
    if (instr.len == 0) return .no_instructions;

    const ctx = obj.get("context").?;
    const ctx_obj = objOf(ctx) orelse return .bad_context;
    const ctx_version = s(ctx_obj.get("schema_version"));
    if (eqStr(ctx_version, "zentinel.ai.context.v1")) {
        if (context.validate(ctx) != .ok) return .bad_context;
    } else {
        return .unknown_context_schema;
    }

    const rs = objOf(obj.get("response_schema").?) orelse return .bad_response_schema;
    if (!eqStr(s(rs.get("name")), responseSchemaName(flow))) return .bad_response_schema;
    return .ok;
}

// --- Deterministic stub provider + typed responses -------------------------

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
    title: []const u8,
    test_name: []const u8,
    intent: []const u8,
    example_values: []const []const u8,
    target_file: []const u8,
};

const SuggestResponse = struct {
    schema_version: []const u8 = "zentinel.ai.suggest.response.v1",
    classification: []const u8,
    suggestions: []const Suggestion,
};

const Cluster = struct {
    classification: []const u8,
    mutant_ids: []const []const u8,
    summary: []const u8,
    recommended_focus: []const u8,
};

const ReviewTestsResponse = struct {
    schema_version: []const u8 = "zentinel.ai.review_tests.response.v1",
    clusters: []const Cluster,
    top_actions: []const []const u8,
};

const Response = union(Flow) {
    explain: ExplainResponse,
    suggest: SuggestResponse,
    review_tests: ReviewTestsResponse,
};

/// Stub classification mapping (docs/AI_PROMPT_CONTRACTS.md, Stub Provider).
fn mapClassification(operator: []const u8, status: []const u8) []const u8 {
    if (!eqStr(status, "survived")) return "unclear";
    if (contains(operator, "comparison") or contains(operator, "boundary")) return "boundary_missing";
    if (contains(operator, "optional") or contains(operator, "null")) return "null_path_missing";
    if (contains(operator, "errdefer") or contains(operator, "cleanup")) return "cleanup_path_missing";
    if (contains(operator, "error")) return "error_path_missing";
    if (contains(operator, "logical") or contains(operator, "boolean")) return "logical_case_missing";
    if (contains(operator, "comptime")) return "comptime_case_missing";
    if (contains(operator, "literal") or contains(operator, "constant")) return "constant_case_missing";
    return "unclear";
}

fn categoryWord(classification: []const u8) []const u8 {
    if (eqStr(classification, "boundary_missing")) return "boundary";
    if (eqStr(classification, "null_path_missing")) return "null-path";
    if (eqStr(classification, "error_path_missing")) return "error-path";
    if (eqStr(classification, "cleanup_path_missing")) return "cleanup-path";
    if (eqStr(classification, "logical_case_missing")) return "logical-case";
    if (eqStr(classification, "comptime_case_missing")) return "comptime-case";
    if (eqStr(classification, "constant_case_missing")) return "constant-case";
    if (eqStr(classification, "possibly_equivalent")) return "possibly-equivalent";
    return "uncovered";
}

fn stubMutantResponse(arena: std.mem.Allocator, flow: Flow, mutant: std.json.Value, patterns: []const []const u8) redaction.Error!Response {
    const operator = s(get(mutant, "operator"));
    const status = s(getO(get(mutant, "result"), "status"));
    const classification = mapClassification(operator, status);
    const word = categoryWord(classification);
    // Redact the file path the stub echoes into its advisory text so the rendered
    // output (stdout) never leaks an absolute path or secret-looking token (F-4).
    var sink = context.RedactionLog.init(arena);
    const file = try context.redactField(arena, s(get(mutant, "file")), patterns, &sink);
    switch (flow) {
        .explain => {
            const confidence: []const u8 = if (eqStr(classification, "unclear")) "unclear" else "medium";
            const refs = try arena.alloc(EvidenceRef, 1);
            refs[0] = .{ .kind = "mutant_diff", .ref = operator };
            return .{ .explain = .{
                .classification = classification,
                .confidence = confidence,
                .summary = try std.fmt.allocPrint(arena, "Mutant {s} in {s} ({s}) is {s}; the stub flags a {s} gap.", .{ s(get(mutant, "id")), file, operator, status, word }),
                .evidence_refs = refs,
                .next_action = try std.fmt.allocPrint(arena, "Add a test that exercises the {s} case in {s}.", .{ word, file }),
            } };
        },
        .suggest => {
            const values = try arena.alloc([]const u8, 1);
            values[0] = word;
            const suggestions = try arena.alloc(Suggestion, 1);
            suggestions[0] = .{
                .title = try std.fmt.allocPrint(arena, "cover the {s} case", .{word}),
                .test_name = try std.fmt.allocPrint(arena, "covers {s}", .{word}),
                .intent = try std.fmt.allocPrint(arena, "Assert the {s} behavior so the mutant is killed on rerun.", .{word}),
                .example_values = values,
                .target_file = file,
            };
            return .{ .suggest = .{ .classification = classification, .suggestions = suggestions } };
        },
        .review_tests => unreachable,
    }
}

fn stubReview(arena: std.mem.Allocator, report: std.json.Value) !Response {
    const mutants = arrOf(get(report, "mutants")) orelse &.{};
    const ids = try arena.alloc([]const u8, mutants.len);
    const classes = try arena.alloc([]const u8, mutants.len);
    var n: usize = 0;
    for (mutants) |m| {
        const status = s(getO(get(m, "result"), "status"));
        if (!eqStr(status, "survived")) continue;
        ids[n] = s(get(m, "id"));
        classes[n] = mapClassification(s(get(m, "operator")), status);
        n += 1;
    }

    const clusters = try arena.alloc(Cluster, n);
    const actions = try arena.alloc([]const u8, n);
    var cn: usize = 0;
    outer: for (0..n) |i| {
        for (0..cn) |k| if (eqStr(clusters[k].classification, classes[i])) continue :outer;
        const members = try arena.alloc([]const u8, n);
        var mn: usize = 0;
        for (0..n) |j| if (eqStr(classes[j], classes[i])) {
            members[mn] = ids[j];
            mn += 1;
        };
        clusters[cn] = .{
            .classification = classes[i],
            .mutant_ids = members[0..mn],
            .summary = try std.fmt.allocPrint(arena, "{d} survivor(s) share a {s} gap.", .{ mn, categoryWord(classes[i]) }),
            .recommended_focus = try std.fmt.allocPrint(arena, "Add {s} tests for these survivors.", .{categoryWord(classes[i])}),
        };
        actions[cn] = try std.fmt.allocPrint(arena, "Prioritize {s} coverage ({d} survivor(s)).", .{ categoryWord(classes[i]), mn });
        cn += 1;
    }

    if (cn == 0) {
        const none = try arena.alloc([]const u8, 1);
        none[0] = "No survivors to review.";
        return .{ .review_tests = .{ .clusters = clusters[0..0], .top_actions = none } };
    }
    return .{ .review_tests = .{ .clusters = clusters[0..cn], .top_actions = actions[0..cn] } };
}

fn responseJson(arena: std.mem.Allocator, response: Response) ![]u8 {
    const opts = std.json.Stringify.Options{ .whitespace = .indent_2 };
    return switch (response) {
        .explain => |r| std.json.Stringify.valueAlloc(arena, r, opts),
        .suggest => |r| std.json.Stringify.valueAlloc(arena, r, opts),
        .review_tests => |r| std.json.Stringify.valueAlloc(arena, r, opts),
    };
}

// --- Response validation (schema-subset + safety) --------------------------

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
    bad_mutant_id,
};

const explain_classifications = [_][]const u8{
    "boundary_missing",                "null_path_missing",         "error_path_missing",
    "cleanup_path_missing",            "comptime_case_missing",     "logical_case_missing",
    "constant_case_missing",           "doctest_output_mismatch",   "doctest_invalid_example",
    "doctest_snapshot_wording_change", "doctest_assertion_missing", "doctest_survivor_missing_assertion",
    "possibly_equivalent",             "unclear",
};
const mutation_classifications = [_][]const u8{
    "boundary_missing",      "null_path_missing",     "error_path_missing",
    "cleanup_path_missing",  "comptime_case_missing", "logical_case_missing",
    "constant_case_missing", "possibly_equivalent",   "unclear",
};
const confidences = [_][]const u8{ "low", "medium", "high", "unclear" };

const unsafe_markers = [_][]const u8{
    "ignore previous", "ignore all previous", "disregard previous",
    "<tool",           "</tool",              "```tool",
    "system:",         "assistant:",          "<|",
    "begin_of_text",
};

fn unsafeText(text: []const u8) bool {
    for (unsafe_markers) |marker| {
        if (std.ascii.indexOfIgnoreCase(text, marker) != null) return true;
    }
    return false;
}

fn projectRelative(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path[0] == '/' or path[0] == '~' or path[0] == '\\') return false;
    if (path.len >= 2 and path[1] == ':') return false; // drive-letter absolute
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    return true;
}

fn onlyKeys(obj: std.json.ObjectMap, allowed: []const []const u8) bool {
    for (obj.keys()) |k| if (!inSet(k, allowed)) return false;
    return true;
}
fn requireKeys(obj: std.json.ObjectMap, keys: []const []const u8) bool {
    for (keys) |k| if (obj.get(k) == null) return false;
    return true;
}

/// Validate a model response against its flow's closed schema and reject unsafe
/// output: unknown fields (including any attempt to set a status), unknown
/// classification/confidence, over-long suggestion lists, non-project-relative
/// target paths, hidden tool instructions, and non-durable mutant ids.
pub fn validateResponse(flow: Flow, value: std.json.Value) ResponseViolation {
    const obj = objOf(value) orelse return .not_object;
    switch (flow) {
        .explain => {
            const allowed = [_][]const u8{ "schema_version", "classification", "confidence", "summary", "evidence_refs", "next_action" };
            if (!requireKeys(obj, &allowed)) return .missing_field;
            if (!onlyKeys(obj, &allowed)) return .unknown_field;
            if (!eqStr(s(obj.get("schema_version")), "zentinel.ai.explain.response.v1")) return .bad_schema_version;
            if (!inSet(s(obj.get("classification")), &explain_classifications)) return .bad_enum;
            if (!inSet(s(obj.get("confidence")), &confidences)) return .bad_enum;
            const summary = s(obj.get("summary"));
            if (summary.len == 0) return .empty_summary;
            if (unsafeText(summary) or unsafeText(s(obj.get("next_action")))) return .unsafe_text;
            const refs = arrOf(obj.get("evidence_refs")) orelse return .not_array;
            for (refs) |r| {
                const ro = objOf(r) orelse return .not_object;
                if (!requireKeys(ro, &.{ "kind", "ref" })) return .missing_field;
                if (!onlyKeys(ro, &.{ "kind", "ref" })) return .unknown_field;
                if (unsafeText(s(ro.get("ref")))) return .unsafe_text;
            }
            return .ok;
        },
        .suggest => {
            const allowed = [_][]const u8{ "schema_version", "classification", "suggestions" };
            if (!requireKeys(obj, &allowed)) return .missing_field;
            if (!onlyKeys(obj, &allowed)) return .unknown_field;
            if (!eqStr(s(obj.get("schema_version")), "zentinel.ai.suggest.response.v1")) return .bad_schema_version;
            if (!inSet(s(obj.get("classification")), &mutation_classifications)) return .bad_enum;
            const suggestions = arrOf(obj.get("suggestions")) orelse return .not_array;
            if (suggestions.len == 0) return .missing_field;
            if (suggestions.len > 3) return .too_many_suggestions;
            const fields = [_][]const u8{ "title", "test_name", "intent", "example_values", "target_file" };
            for (suggestions) |sg| {
                const so = objOf(sg) orelse return .not_object;
                if (!requireKeys(so, &fields)) return .missing_field;
                if (!onlyKeys(so, &fields)) return .unknown_field;
                if (unsafeText(s(so.get("title"))) or unsafeText(s(so.get("intent"))) or unsafeText(s(so.get("test_name")))) return .unsafe_text;
                if (!projectRelative(s(so.get("target_file")))) return .bad_path;
                const values = arrOf(so.get("example_values")) orelse return .not_array;
                for (values) |v| switch (v) {
                    .string => {},
                    else => return .bad_enum,
                };
            }
            return .ok;
        },
        .review_tests => {
            const allowed = [_][]const u8{ "schema_version", "clusters", "top_actions" };
            if (!requireKeys(obj, &allowed)) return .missing_field;
            if (!onlyKeys(obj, &allowed)) return .unknown_field;
            if (!eqStr(s(obj.get("schema_version")), "zentinel.ai.review_tests.response.v1")) return .bad_schema_version;
            const clusters = arrOf(obj.get("clusters")) orelse return .not_array;
            const fields = [_][]const u8{ "classification", "mutant_ids", "summary", "recommended_focus" };
            for (clusters) |c| {
                const co = objOf(c) orelse return .not_object;
                if (!requireKeys(co, &fields)) return .missing_field;
                if (!onlyKeys(co, &fields)) return .unknown_field;
                if (!inSet(s(co.get("classification")), &mutation_classifications)) return .bad_enum;
                if (unsafeText(s(co.get("summary"))) or unsafeText(s(co.get("recommended_focus")))) return .unsafe_text;
                const ids = arrOf(co.get("mutant_ids")) orelse return .not_array;
                for (ids) |idv| {
                    const id = switch (idv) {
                        .string => |t| t,
                        else => return .bad_mutant_id,
                    };
                    if (!std.mem.startsWith(u8, id, "m_") or id.len < 3) return .bad_mutant_id;
                }
            }
            const actions = arrOf(obj.get("top_actions")) orelse return .not_array;
            for (actions) |a| switch (a) {
                .string => |t| if (unsafeText(t)) return .unsafe_text,
                else => return .bad_enum,
            };
            return .ok;
        },
    }
}

// --- Rendering -------------------------------------------------------------

fn renderText(arena: std.mem.Allocator, response: Response) ![]u8 {
    return switch (response) {
        .explain => |r| std.fmt.allocPrint(arena,
            \\classification: {s}
            \\confidence: {s}
            \\summary: {s}
            \\next action: {s}
            \\
        , .{ r.classification, r.confidence, r.summary, r.next_action }),
        .suggest => |r| blk: {
            var body = try std.fmt.allocPrint(arena, "classification: {s}\nsuggestions:\n", .{r.classification});
            for (r.suggestions, 0..) |sg, idx| {
                body = try std.fmt.allocPrint(arena, "{s}{d}. {s}\n   test: {s}\n   intent: {s}\n   target: {s}\n", .{ body, idx + 1, sg.title, sg.test_name, sg.intent, sg.target_file });
            }
            break :blk body;
        },
        .review_tests => |r| blk: {
            var body = try std.fmt.allocPrint(arena, "clusters: {d}\n", .{r.clusters.len});
            for (r.clusters) |c| {
                body = try std.fmt.allocPrint(arena, "{s}- {s} ({d}): {s}\n", .{ body, c.classification, c.mutant_ids.len, c.summary });
            }
            body = try std.fmt.allocPrint(arena, "{s}top actions:\n", .{body});
            for (r.top_actions) |a| {
                body = try std.fmt.allocPrint(arena, "{s}- {s}\n", .{ body, a });
            }
            break :blk body;
        },
    };
}

// --- Top-level command run -------------------------------------------------

pub const Format = enum { text, json };

pub const Outcome = struct {
    exit_code: u8,
    body: []const u8,
    format: Format,
};

pub const Input = struct {
    flow: Flow,
    /// Required for `explain`/`suggest`; ignored (null) for `review-tests`.
    mutant_ref: ?[]const u8,
    /// Command-local `--ai-provider` override; null means use config.
    provider_override: ?Mode,
    /// Report bytes from `--input-report` or the default path; null means the
    /// report could not be read (a usage error).
    report_json: ?[]const u8,
    settings: Settings,
};

/// Run one advisory AI command end to end: resolve the provider, parse the
/// read-only report, resolve the target, build and validate the prompt envelope,
/// call the (stub) provider, validate the response, and render it. Returns a
/// `Failure` for every AI-only error; never mutates the report.
pub fn run(arena: std.mem.Allocator, input: Input, format: Format) RunError!Outcome {
    const mode = try resolveMode(input.settings, input.provider_override);

    const bytes = input.report_json orelse return error.AiReportNotFound;
    const report = std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{}) catch return error.AiReportNotFound;
    if (objOf(report) == null or get(report, "mutants") == null) return error.AiReportNotFound;

    var anchor: ?std.json.Value = null;
    const response: Response = switch (input.flow) {
        .explain, .suggest => blk: {
            const ref = input.mutant_ref orelse return error.AiTargetNotFound;
            const mutant = resolveMutant(report, ref) orelse return error.AiTargetNotFound;
            anchor = mutant;
            break :blk stubMutantResponse(arena, input.flow, mutant, input.settings.redact_patterns) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.RedactionFailed => return error.AiResponseInvalid,
            };
        },
        .review_tests => blk: {
            anchor = firstSurvivor(report);
            break :blk stubReview(arena, report) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
            };
        },
    };

    // Build and validate the prompt request envelope before "sending" it.
    if (anchor) |mutant| {
        const prompt = buildPromptValue(arena, input.flow, mode, mutant, report, input.settings) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            // An out-of-range or non-integer report integer is an invalid report,
            // not a bad model response (task 107).
            error.AiReportNotFound => return error.AiReportNotFound,
            else => return error.AiResponseInvalid,
        };
        if (validatePrompt(prompt) != .ok) return error.AiResponseInvalid;
    }

    // Serialize and validate the response before rendering.
    const json = try responseJson(arena, response);
    const value = std.json.parseFromSliceLeaky(std.json.Value, arena, json, .{}) catch return error.AiResponseInvalid;
    if (validateResponse(input.flow, value) != .ok) return error.AiResponseInvalid;

    const body = switch (format) {
        .json => json,
        .text => try renderText(arena, response),
    };
    return .{ .exit_code = 0, .body = body, .format = format };
}
