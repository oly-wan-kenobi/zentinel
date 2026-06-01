// Layer: deterministic_core
//
// AI context construction and validation (docs/AI_CONTEXT_SCHEMA.md,
// schemas/ai.context.v1.schema.json). The context is the only payload a provider
// sees; it is built deterministically from the report model with privacy
// redaction and bounded source/evidence excerpts, and it carries no field the
// deterministic core derives in a way a provider could write back. This module
// owns the typed context model (serialized in canonical order for stable prompt
// snapshots), a UTF-8-safe excerpt cap applied before schema validation, the
// redact-then-cap helper that fails closed, and a structural validator that
// enforces the nested object shapes the schema requires.
const std = @import("std");
const redaction = @import("redaction.zig");

/// Primary excerpt bound: stdout/stderr excerpts are capped to this many UTF-8
/// bytes on a safe character boundary before validation; the schema `maxLength`
/// is a secondary structural guard.
pub const excerpt_limit: usize = 4096;

// --- Typed context model (canonical field order) ---------------------------

pub const Span = struct {
    byte_start: u64,
    byte_end: u64,
    line_start: u32,
    column_start: u32,
    line_end: u32,
    column_end: u32,
};

pub const Evidence = struct {
    stdout_excerpt: []const u8,
    stderr_excerpt: []const u8,
    failure_summary: []const u8,
};

pub const CommandEvidence = struct {
    original: []const u8,
    argv: []const []const u8,
    cwd: []const u8,
    environment_policy: []const u8 = "minimal",
    shell: bool = false,
};

pub const CommandResult = struct {
    command: CommandEvidence,
    phase: []const u8 = "mutant",
    status: []const u8,
    exit_code: ?i64,
    timed_out: bool,
    failure_kind: []const u8,
    duration_ms_normalized: []const u8 = "<duration>",
    evidence: Evidence,
    skip_reason: ?[]const u8,
};

pub const MutantCtx = struct {
    id: []const u8,
    display_id: u32,
    backend: []const u8,
    backend_stability: []const u8,
    operator: []const u8,
    operator_stability: []const u8,
    file: []const u8,
    span: Span,
    original: []const u8,
    replacement: []const u8,
    diff: []const []const u8,
    expected_compile: []const u8,
};

pub const ResultCtx = struct {
    status: []const u8,
    mode: []const u8,
    commands: []const CommandResult,
    phase: []const u8 = "mutant",
    duration_ms_normalized: []const u8 = "<duration>",
    evidence: Evidence,
    skip_reason: ?[]const u8,
};

pub const SourceSymbol = struct {
    kind: []const u8,
    name: []const u8,
    line: u32,
};

pub const SourceContext = struct {
    policy: []const u8,
    language: []const u8 = "zig",
    before_lines: u32,
    after_lines: u32,
    snippet: []const []const u8,
    symbols: []const SourceSymbol,
};

pub const SelectedTest = struct {
    name: []const u8,
    file: []const u8,
    line: u32,
};

pub const TestContext = struct {
    selection_reason: []const u8,
    selected_tests: []const SelectedTest,
    baseline_status: []const u8,
    same_file_tests_excluded_from_mutation: bool,
};

pub const Operator = struct {
    name: []const u8,
    category: []const u8,
    equivalent_risks: []const []const u8,
    suggested_test_focus: []const []const u8,
};

pub const Privacy = struct {
    redactions_applied: []const []const u8,
    source_context_policy: []const u8,
    remote_allowed: bool,
};

pub const Project = struct {
    name: []const u8,
    root_label: []const u8,
    zig_version: []const u8,
    zentinel_version: []const u8,
};

pub const Context = struct {
    schema_version: []const u8 = "zentinel.ai.context.v1",
    flow: []const u8,
    created_by: []const u8 = "zentinel",
    provider_mode: []const u8,
    privacy: Privacy,
    project: Project,
    mutant: MutantCtx,
    result: ResultCtx,
    source_context: SourceContext,
    test_context: TestContext,
    operator: Operator,
};

/// Deterministic pretty-printed JSON for a context, in canonical field order.
pub fn toJson(arena: std.mem.Allocator, ctx: Context) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, ctx, .{ .whitespace = .indent_2 });
}

// --- Excerpt bounding + redaction integration ------------------------------

/// Cap `text` to at most `max_bytes` UTF-8 bytes on a character boundary, so an
/// excerpt is never truncated mid-codepoint before schema validation.
pub fn capExcerpt(arena: std.mem.Allocator, text: []const u8, max_bytes: usize) std.mem.Allocator.Error![]const u8 {
    if (text.len <= max_bytes) return arena.dupe(u8, text);
    var end = max_bytes;
    // Back up off any UTF-8 continuation byte (0b10xxxxxx) so we cut on a
    // codepoint boundary.
    while (end > 0 and (text[end] & 0xC0) == 0x80) end -= 1;
    return arena.dupe(u8, text[0..end]);
}

/// Redact then cap one evidence excerpt. Fails closed: if redaction cannot be
/// applied the whole AI flow must abort rather than risk leaking a secret.
pub fn redactAndCap(arena: std.mem.Allocator, text: []const u8, patterns: []const []const u8, max_bytes: usize) redaction.Error![]const u8 {
    const r = try redaction.redact(arena, text, patterns);
    return capExcerpt(arena, r.text, max_bytes);
}

/// Synthetic `redactions_applied` labels for redaction kinds that are not
/// configured patterns (docs/AI_CONTEXT_SCHEMA.md). `absolute_path` marks an
/// absolute path normalized to `<path>`; `secret_value` marks a built-in
/// secret-VALUE shape scrubbed (GitHub/AWS/Anthropic/JWT/PEM).
pub const label_absolute_path = "absolute_path";
pub const label_secret_value = "secret_value";

/// Accumulates the redaction labels actually applied across every context field,
/// deduplicated in first-seen order, so `privacy.redactions_applied` is truthful:
/// non-empty exactly when at least one redaction occurred.
pub const RedactionLog = struct {
    arena: std.mem.Allocator,
    labels: std.ArrayList([]const u8) = .empty,

    pub fn init(arena: std.mem.Allocator) RedactionLog {
        return .{ .arena = arena };
    }

    fn has(self: RedactionLog, label: []const u8) bool {
        for (self.labels.items) |l| {
            if (std.mem.eql(u8, l, label)) return true;
        }
        return false;
    }

    pub fn add(self: *RedactionLog, label: []const u8) std.mem.Allocator.Error!void {
        if (!self.has(label)) try self.labels.append(self.arena, label);
    }

    pub fn applied(self: RedactionLog) []const []const u8 {
        return self.labels.items;
    }
};

/// Redact a path/source-bearing context field: normalize absolute paths to
/// `<path>` and scrub secret-looking tokens, recording every redaction kind
/// applied into `log`. Fails closed like `redact`. Used for the file, source,
/// diff, and path fields that previously passed through verbatim (audit F-4).
pub fn redactField(arena: std.mem.Allocator, text: []const u8, patterns: []const []const u8, log: *RedactionLog) redaction.Error![]const u8 {
    const np = try redaction.normalizeAbsolutePaths(arena, text);
    if (np.changed) try log.add(label_absolute_path);
    const r = try redaction.redact(arena, np.text, patterns);
    for (r.applied) |p| try log.add(p);
    if (r.builtin_matched) try log.add(label_secret_value);
    return r.text;
}

/// Redact every line of a string array (e.g. a `diff` or `mutated_diff`) through
/// `redactField`, accumulating into `log`.
pub fn redactStrArray(arena: std.mem.Allocator, lines: []const []const u8, patterns: []const []const u8, log: *RedactionLog) redaction.Error![]const []const u8 {
    const out = try arena.alloc([]const u8, lines.len);
    for (lines, 0..) |line, i| out[i] = try redactField(arena, line, patterns, log);
    return out;
}

/// Redact + cap one evidence excerpt while recording the redactions into `log`,
/// so evidence-sourced secrets are reflected in `redactions_applied` too.
pub fn redactAndCapLogged(arena: std.mem.Allocator, text: []const u8, patterns: []const []const u8, max_bytes: usize, log: *RedactionLog) redaction.Error![]const u8 {
    const r = try redaction.redact(arena, text, patterns);
    for (r.applied) |p| try log.add(p);
    if (r.builtin_matched) try log.add(label_secret_value);
    return capExcerpt(arena, r.text, max_bytes);
}

// --- Structural validation (schema-subset, JSON level) ---------------------

pub const Violation = enum {
    ok,
    not_object,
    missing_field,
    bad_enum,
    bad_argv0,
    bad_environment_policy,
    bad_shell,
    skip_reason_rule,
    excerpt_too_long,
    legacy_command_shape,
};

fn asObject(v: std.json.Value) ?std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
        else => null,
    };
}
fn asString(v: std.json.Value) ?[]const u8 {
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}
fn fieldStr(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    return if (obj.get(key)) |v| asString(v) else null;
}
fn inSet(needle: []const u8, set: []const []const u8) bool {
    for (set) |s| {
        if (std.mem.eql(u8, needle, s)) return true;
    }
    return false;
}
fn enumOk(obj: std.json.ObjectMap, key: []const u8, set: []const []const u8) bool {
    const s = fieldStr(obj, key) orelse return false;
    return inSet(s, set);
}
fn requireAll(obj: std.json.ObjectMap, keys: []const []const u8) bool {
    for (keys) |k| {
        if (obj.get(k) == null) return false;
    }
    return true;
}

const result_statuses = [_][]const u8{ "killed", "survived", "compile_error", "compiler_crash", "timeout", "skipped", "invalid" };
const command_statuses = [_][]const u8{ "passed", "failed", "compiler_crash", "timeout", "skipped" };
const modes = [_][]const u8{ "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall" };

fn validateEvidence(v: std.json.Value) Violation {
    const ev = asObject(v) orelse return .not_object;
    if (!requireAll(ev, &.{ "stdout_excerpt", "stderr_excerpt", "failure_summary" })) return .missing_field;
    inline for (.{ "stdout_excerpt", "stderr_excerpt" }) |k| {
        const s = fieldStr(ev, k) orelse return .missing_field;
        if (s.len > excerpt_limit) return .excerpt_too_long;
    }
    return .ok;
}

/// `skipped` status requires a non-empty string skip_reason; any other status
/// requires skip_reason to be null.
fn validateSkip(obj: std.json.ObjectMap) Violation {
    const status = fieldStr(obj, "status") orelse return .missing_field;
    const sr = obj.get("skip_reason") orelse return .missing_field;
    if (std.mem.eql(u8, status, "skipped")) {
        const s = asString(sr) orelse return .skip_reason_rule;
        if (s.len == 0) return .skip_reason_rule;
    } else {
        if (sr != .null) return .skip_reason_rule;
    }
    return .ok;
}

fn validateCommand(v: std.json.Value) Violation {
    const c = asObject(v) orelse return .not_object;
    if (!requireAll(c, &.{ "command", "phase", "status", "exit_code", "timed_out", "failure_kind", "duration_ms_normalized", "evidence", "skip_reason" })) return .missing_field;
    if (!enumOk(c, "status", &command_statuses)) return .bad_enum;
    if (!enumOk(c, "phase", &.{"mutant"})) return .bad_enum;

    const cmd = asObject(c.get("command").?) orelse return .not_object;
    if (!requireAll(cmd, &.{ "original", "argv", "cwd", "environment_policy", "shell" })) return .missing_field;
    if (!enumOk(cmd, "environment_policy", &.{"minimal"})) return .bad_environment_policy;
    const shell = cmd.get("shell").?;
    if (shell != .bool or shell.bool != false) return .bad_shell;
    const argv = switch (cmd.get("argv").?) {
        .array => |arr| arr.items,
        else => return .bad_argv0,
    };
    if (argv.len == 0) return .bad_argv0;
    const argv0 = asString(argv[0]) orelse return .bad_argv0;
    if (argv0.len == 0) return .bad_argv0;

    const sv = validateSkip(c);
    if (sv != .ok) return sv;
    return validateEvidence(c.get("evidence").?);
}

/// Validate a parsed AI context JSON value against the v1 nested object shapes.
/// Returns `.ok` or the first violation. This is the deterministic structural
/// gate that backs the schema; it rejects generic objects, legacy single-command
/// result shapes, empty argv[0], non-`minimal` environment policy, a shell
/// command, malformed skip reasons, over-long excerpts, and `preview` used as a
/// backend stability.
pub fn validate(value: std.json.Value) Violation {
    const obj = asObject(value) orelse return .not_object;
    if (!requireAll(obj, &.{ "schema_version", "flow", "created_by", "provider_mode", "privacy", "project", "mutant", "result", "source_context", "test_context", "operator" })) return .missing_field;
    if (!enumOk(obj, "schema_version", &.{"zentinel.ai.context.v1"})) return .bad_enum;
    if (!enumOk(obj, "flow", &.{ "explain", "suggest", "review_tests" })) return .bad_enum;
    if (!enumOk(obj, "created_by", &.{"zentinel"})) return .bad_enum;
    if (!enumOk(obj, "provider_mode", &.{ "disabled", "stub", "local", "remote" })) return .bad_enum;

    // privacy / project
    const privacy = asObject(obj.get("privacy").?) orelse return .not_object;
    if (!requireAll(privacy, &.{ "redactions_applied", "source_context_policy", "remote_allowed" })) return .missing_field;
    if (!enumOk(privacy, "source_context_policy", &.{ "minimal", "none" })) return .bad_enum;
    const project = asObject(obj.get("project").?) orelse return .not_object;
    if (!requireAll(project, &.{ "name", "root_label", "zig_version", "zentinel_version" })) return .missing_field;

    // mutant: distinct backend vs operator stability
    const m = asObject(obj.get("mutant").?) orelse return .not_object;
    if (!requireAll(m, &.{ "id", "display_id", "backend", "backend_stability", "operator", "operator_stability", "file", "span", "original", "replacement", "diff", "expected_compile" })) return .missing_field;
    if (!enumOk(m, "backend", &.{ "ast", "zir", "air" })) return .bad_enum;
    if (!enumOk(m, "backend_stability", &.{ "stable", "experimental" })) return .bad_enum; // rejects `preview`
    if (!enumOk(m, "operator_stability", &.{ "stable", "preview", "experimental" })) return .bad_enum; // accepts `preview`
    if (!enumOk(m, "expected_compile", &.{ "compiles", "may_fail", "must_fail" })) return .bad_enum;

    // result: structured commands array, no legacy single-command shapes
    const r = asObject(obj.get("result").?) orelse return .not_object;
    if (r.get("command") != null or r.get("test_command") != null) return .legacy_command_shape;
    if (!requireAll(r, &.{ "status", "mode", "commands", "phase", "duration_ms_normalized", "evidence", "skip_reason" })) return .missing_field;
    if (!enumOk(r, "status", &result_statuses)) return .bad_enum;
    if (!enumOk(r, "mode", &modes)) return .bad_enum;
    if (!enumOk(r, "phase", &.{"mutant"})) return .bad_enum;
    const rsv = validateSkip(r);
    if (rsv != .ok) return rsv;
    const rev = validateEvidence(r.get("evidence").?);
    if (rev != .ok) return rev;
    const commands = switch (r.get("commands").?) {
        .array => |arr| arr.items,
        else => return .missing_field,
    };
    for (commands) |c| {
        const cv = validateCommand(c);
        if (cv != .ok) return cv;
    }

    // source_context / test_context / operator
    const sc = asObject(obj.get("source_context").?) orelse return .not_object;
    if (!requireAll(sc, &.{ "policy", "language", "before_lines", "after_lines", "snippet", "symbols" })) return .missing_field;
    if (!enumOk(sc, "policy", &.{ "minimal", "none" })) return .bad_enum;
    if (!enumOk(sc, "language", &.{"zig"})) return .bad_enum;
    const tc = asObject(obj.get("test_context").?) orelse return .not_object;
    if (!requireAll(tc, &.{ "selection_reason", "selected_tests", "baseline_status", "same_file_tests_excluded_from_mutation" })) return .missing_field;
    if (!enumOk(tc, "baseline_status", &.{ "passed", "failed", "unknown" })) return .bad_enum;
    const op = asObject(obj.get("operator").?) orelse return .not_object;
    if (!requireAll(op, &.{ "name", "category", "equivalent_risks", "suggested_test_focus" })) return .missing_field;

    return .ok;
}
