const std = @import("std");
const zentinel = @import("zentinel");

const context = zentinel.ai.context;
const provider = zentinel.ai.provider;
const redaction = zentinel.ai.redaction;
const config = zentinel.config;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

// --- A complete, valid context (canonical shape) ---------------------------

const default_command = context.CommandResult{
    .command = .{
        .original = "zig build test",
        .argv = &.{ "zig", "build", "test" },
        .cwd = "<project>",
    },
    .status = "failed",
    .exit_code = 1,
    .timed_out = false,
    .failure_kind = "test_failure",
    .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "boom", .failure_summary = "ZNTL_RUNNER_COMMAND_FAILED" },
    .skip_reason = null,
};
const default_commands = [_]context.CommandResult{default_command};

fn validCommand() context.CommandResult {
    return default_command;
}

fn validContext() context.Context {
    return .{
        .flow = "explain",
        .provider_mode = "stub",
        .privacy = .{ .redactions_applied = &.{}, .source_context_policy = "minimal", .remote_allowed = false },
        .project = .{ .name = "demo", .root_label = "<project>", .zig_version = "0.16.0", .zentinel_version = "0.0.0" },
        .mutant = .{
            .id = "m_abc123",
            .display_id = 1,
            .backend = "ast",
            .backend_stability = "stable",
            .operator = "arithmetic_add_sub",
            .operator_stability = "stable",
            .file = "src/x.zig",
            .span = .{ .byte_start = 41, .byte_end = 42, .line_start = 2, .column_start = 14, .line_end = 2, .column_end = 15 },
            .original = "+",
            .replacement = "-",
            .diff = &.{ "- return a + b;", "+ return a - b;" },
            .expected_compile = "compiles",
        },
        .result = .{
            .status = "killed",
            .mode = "Debug",
            .commands = &default_commands,
            .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "boom", .failure_summary = "ZNTL_RUNNER_COMMAND_FAILED" },
            .skip_reason = null,
        },
        .source_context = .{
            .policy = "minimal",
            .before_lines = 1,
            .after_lines = 1,
            .snippet = &.{ "pub fn add(a: i32, b: i32) i32 {", "    return a + b;", "}" },
            .symbols = &.{.{ .kind = "fn", .name = "add", .line = 1 }},
        },
        .test_context = .{
            .selection_reason = "same_file",
            .selected_tests = &.{.{ .name = "add works", .file = "src/x.zig", .line = 6 }},
            .baseline_status = "passed",
            .same_file_tests_excluded_from_mutation = true,
        },
        .operator = .{
            .name = "arithmetic_add_sub",
            .category = "arithmetic",
            .equivalent_risks = &.{},
            .suggested_test_focus = &.{"boundary values"},
        },
    };
}

fn parse(a: std.mem.Allocator, json: []const u8) std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, a, json, .{}) catch @panic("invalid json");
}

fn validateJson(a: std.mem.Allocator, ctx: context.Context) context.Violation {
    const json = context.toJson(a, ctx) catch @panic("oom");
    var parsed = parse(a, json);
    defer parsed.deinit();
    return context.validate(parsed.value);
}

// --- Schema conformance + snapshot -----------------------------------------

const valid_snapshot = @embedFile("fixtures/ai/context/valid.json");

test "a built AI context validates against the schema and matches the snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const json = try context.toJson(a, validContext());
    try expectEqualStrings(valid_snapshot, json);

    var parsed = parse(a, json);
    defer parsed.deinit();
    try expectEqual(context.Violation.ok, context.validate(parsed.value));
}

test "a context missing a required nested object is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const json = try context.toJson(a, validContext());

    inline for (.{ "mutant", "result", "source_context", "test_context", "operator" }) |key| {
        var parsed = parse(a, json);
        defer parsed.deinit();
        _ = parsed.value.object.orderedRemove(key);
        try expectEqual(context.Violation.missing_field, context.validate(parsed.value));
    }

    // A nested required field (mutant.backend_stability) missing is also rejected.
    var parsed = parse(a, json);
    defer parsed.deinit();
    _ = parsed.value.object.getPtr("mutant").?.object.orderedRemove("backend_stability");
    try expectEqual(context.Violation.missing_field, context.validate(parsed.value));
}

test "schema minimum/minLength/pattern constraints are enforced" {
    // Regression: the in-process validator used to ignore the schema's minimum
    // (display_id/span >= 1), minLength (file/operator/name >= 1), and id-prefix
    // constraints, so an untrusted --input-report with display_id: 0 or a
    // malformed mutant id passed locally while violating the published schema.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try context.toJson(a, validContext());

    // display_id < 1 -> rejected.
    {
        var parsed = parse(a, base);
        defer parsed.deinit();
        parsed.value.object.getPtr("mutant").?.object.getPtr("display_id").?.* = .{ .integer = 0 };
        try expectEqual(context.Violation.bad_constraint, context.validate(parsed.value));
    }
    // span.line_start < 1 -> rejected.
    {
        var parsed = parse(a, base);
        defer parsed.deinit();
        parsed.value.object.getPtr("mutant").?.object.getPtr("span").?.object.getPtr("line_start").?.* = .{ .integer = 0 };
        try expectEqual(context.Violation.bad_constraint, context.validate(parsed.value));
    }
    // mutant.id without the m_ prefix (and not a privacy placeholder) -> rejected.
    {
        var parsed = parse(a, base);
        defer parsed.deinit();
        parsed.value.object.getPtr("mutant").?.object.getPtr("id").?.* = .{ .string = "not-a-real-id" };
        try expectEqual(context.Violation.bad_constraint, context.validate(parsed.value));
    }
    // A privacy placeholder id ([REDACTED] / <path>) is accepted (privacy wins).
    {
        var parsed = parse(a, base);
        defer parsed.deinit();
        parsed.value.object.getPtr("mutant").?.object.getPtr("id").?.* = .{ .string = "[REDACTED]" };
        try expectEqual(context.Violation.ok, context.validate(parsed.value));
    }
}

// --- Result command shape rules --------------------------------------------

test "result uses the structured commands array and rejects legacy single-command payloads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const json = try context.toJson(a, validContext());

    inline for (.{ "command", "test_command" }) |legacy| {
        var parsed = parse(a, json);
        defer parsed.deinit();
        // A legacy single-`command` or `test_command`-only payload must be rejected.
        try parsed.value.object.getPtr("result").?.object.put(a, legacy, .{ .string = "zig build test" });
        try expectEqual(context.Violation.legacy_command_shape, context.validate(parsed.value));
    }
}

test "result command evidence rejects empty argv0, non-minimal environment policy, and a shell command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    {
        var ctx = validContext();
        var cmd = validCommand();
        cmd.command.argv = &.{""};
        ctx.result.commands = &.{cmd};
        try expectEqual(context.Violation.bad_argv0, validateJson(a, ctx));
    }
    {
        var ctx = validContext();
        var cmd = validCommand();
        cmd.command.environment_policy = "host";
        ctx.result.commands = &.{cmd};
        try expectEqual(context.Violation.bad_environment_policy, validateJson(a, ctx));
    }
    {
        var ctx = validContext();
        var cmd = validCommand();
        cmd.command.shell = true;
        ctx.result.commands = &.{cmd};
        try expectEqual(context.Violation.bad_shell, validateJson(a, ctx));
    }
}

test "result command evidence rejects unknown failure kinds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ctx = validContext();
    var cmd = validCommand();
    cmd.failure_kind = "prompt_injected";
    ctx.result.commands = &.{cmd};
    try expectEqual(context.Violation.bad_enum, validateJson(a, ctx));
}

test "skipped entries require deterministic skip reasons; non-skipped require null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A skipped command with a null skip_reason is rejected.
    {
        var ctx = validContext();
        var cmd = validCommand();
        cmd.status = "skipped";
        cmd.skip_reason = null;
        ctx.result.commands = &.{cmd};
        try expectEqual(context.Violation.skip_reason_rule, validateJson(a, ctx));
    }
    // A non-skipped result with a non-null skip_reason is rejected.
    {
        var ctx = validContext();
        ctx.result.skip_reason = "should be null when not skipped";
        try expectEqual(context.Violation.skip_reason_rule, validateJson(a, ctx));
    }
    // A skipped result with a documented reason is accepted.
    {
        var ctx = validContext();
        ctx.result.status = "skipped";
        ctx.result.skip_reason = "fail-fast: an earlier command decided the result";
        var cmd = validCommand();
        cmd.status = "skipped";
        cmd.skip_reason = "fail-fast: an earlier command decided the result";
        ctx.result.commands = &.{cmd};
        try expectEqual(context.Violation.ok, validateJson(a, ctx));
    }
}

// --- Excerpt bounding -------------------------------------------------------

test "excerpts are capped at 4096 UTF-8 bytes on a safe character boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 4095 ASCII bytes followed by a 3-byte codepoint straddles the 4096 cap.
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendNTimes(a, 'a', 4095);
    try buf.appendSlice(a, "\u{20AC}"); // euro sign, 3 bytes -> total 4098
    const capped = try context.capExcerpt(a, buf.items, context.excerpt_limit);
    try expect(capped.len <= context.excerpt_limit);
    try expect(std.unicode.utf8ValidateSlice(capped)); // never split mid-codepoint
    try expectEqual(@as(usize, 4095), capped.len); // the straddling codepoint is dropped whole

    // A short excerpt is returned unchanged.
    const short = try context.capExcerpt(a, "ok", context.excerpt_limit);
    try expectEqualStrings("ok", short);
}

// --- Backend vs operator stability -----------------------------------------

test "preview is rejected as a backend stability but accepted as an operator stability" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    {
        var ctx = validContext();
        ctx.mutant.backend_stability = "preview";
        try expectEqual(context.Violation.bad_enum, validateJson(a, ctx));
    }
    {
        var ctx = validContext();
        ctx.mutant.operator_stability = "preview";
        try expectEqual(context.Violation.ok, validateJson(a, ctx));
    }
}

// --- Redaction fail-closed --------------------------------------------------

test "redaction redacts default patterns and fails closed on an unsupported pattern" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const patterns = [_][]const u8{ "(?i)api[_-]?key", "(?i)token" };
    const r = try redaction.redact(a, "set API_KEY=secret and token=abc here", &patterns);
    try expect(std.mem.indexOf(u8, r.text, "secret") != null); // only the secret name is redacted, not values
    try expect(std.mem.indexOf(u8, r.text, "API_KEY") == null);
    try expect(std.mem.indexOf(u8, r.text, "token") == null);
    try expect(std.mem.indexOf(u8, r.text, redaction.marker) != null);
    try expectEqual(@as(usize, 2), r.applied.len);

    // An unsupported regex construct fails closed so the AI flow aborts.
    const bad = [_][]const u8{"secret.*key"};
    try expectError(error.RedactionFailed, redaction.redact(a, "secretXXkey", &bad));
    try expectError(error.RedactionFailed, context.redactAndCap(a, "secretXXkey", &bad, context.excerpt_limit));
}

test "value-shaped secrets are redacted from AI context even without a label" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The configured patterns mask only secret LABELS (api_key, token). None of
    // these credentials carry such a label, so before value-shape detection they
    // passed straight through to the provider (adversarial audit finding, task
    // 115): redaction masked the word "api_key" but never the value after it,
    // and an unlabeled secret was emitted verbatim.
    const patterns = [_][]const u8{ "(?i)api[_-]?key", "(?i)token" };

    const github = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const aws = "AKIAIOSFODNN7EXAMPLE";
    const anthropic = "sk-ant-api03-abcdEF0123456789ghijKL";
    const jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N";
    const pem =
        \\-----BEGIN OPENSSH PRIVATE KEY-----
        \\b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAAB
        \\-----END OPENSSH PRIVATE KEY-----
    ;
    const pem_body = "b3BlbnNzaC1rZXktdjEA";

    const text = try std.fmt.allocPrint(
        a,
        "runner stderr: gh={s} aws={s} anthropic={s} jwt={s}\n{s}\n",
        .{ github, aws, anthropic, jwt, pem },
    );

    const r = try redaction.redact(a, text, &patterns);

    // Each realistic secret VALUE must be gone, regardless of the missing label.
    try expect(std.mem.indexOf(u8, r.text, github) == null);
    try expect(std.mem.indexOf(u8, r.text, aws) == null);
    try expect(std.mem.indexOf(u8, r.text, anthropic) == null);
    try expect(std.mem.indexOf(u8, r.text, jwt) == null);
    try expect(std.mem.indexOf(u8, r.text, pem_body) == null);
    try expect(std.mem.indexOf(u8, r.text, redaction.marker) != null);
    // Non-secret context around the secrets is preserved.
    try expect(std.mem.indexOf(u8, r.text, "runner stderr:") != null);

    // The real AI-context path (redact then cap) redacts the same values, so the
    // bounded evidence excerpt a provider receives never carries them.
    const capped = try context.redactAndCap(a, text, &patterns, context.excerpt_limit);
    try expect(std.mem.indexOf(u8, capped, github) == null);
    try expect(std.mem.indexOf(u8, capped, aws) == null);
    try expect(std.mem.indexOf(u8, capped, anthropic) == null);

    // Value-shape detection does not weaken the fail-closed compile contract: a
    // malformed configured pattern still aborts the flow, even when the text
    // contains a value-shaped secret that would otherwise be redacted.
    const bad = [_][]const u8{"secret.*key"};
    try expectError(error.RedactionFailed, redaction.redact(a, github, &bad));
}

test "additional credential shapes (OpenAI, Slack, Google) are redacted by value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const patterns = [_][]const u8{ "(?i)api[_-]?key", "(?i)token" };

    const openai = "sk-proj-abcdEFGH0123456789ijklMNOPqrstUVWX";
    const openai_classic = "sk-ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    const slack = "xoxb-1234567890-ABCDEFGHIJKLMNOP";
    const google = "AIzaSyA1234567890abcdefGHIJKLMNOPQRSTUV";

    const text = try std.fmt.allocPrint(a, "leak openai={s} classic={s} slack={s} google={s}", .{ openai, openai_classic, slack, google });
    const r = try redaction.redact(a, text, &patterns);
    try expect(std.mem.indexOf(u8, r.text, openai) == null);
    try expect(std.mem.indexOf(u8, r.text, openai_classic) == null);
    try expect(std.mem.indexOf(u8, r.text, slack) == null);
    try expect(std.mem.indexOf(u8, r.text, google) == null);
    try expect(r.builtin_matched);
    try expect(std.mem.indexOf(u8, r.text, "leak openai=") != null);

    // A short `sk-` fragment that is not key-shaped must be left untouched.
    const benign = try redaction.redact(a, "use sk-12 today", &patterns);
    try expectEqualStrings("use sk-12 today", benign.text);
}

// --- Config (AI provider + redaction defaults) ------------------------------

test "omitted ai.redact_patterns expands to the default secret patterns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    const cfg = try config.load(arena.allocator(),
        \\[project]
        \\name = "demo"
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
    , &diag);
    try expectEqual(@as(usize, 2), cfg.ai_redact_patterns.len);
    try expectEqualStrings("(?i)api[_-]?key", cfg.ai_redact_patterns[0]);
    try expectEqualStrings("(?i)token", cfg.ai_redact_patterns[1]);
}

test "persisted ai.provider = remote without remote_allowed fails config validation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, config.load(arena.allocator(),
        \\[project]
        \\name = "demo"
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
        \\[ai]
        \\provider = "remote"
        \\
    , &diag));
    try expectEqual(config.Code.invalid_value, diag.code);
    try expectEqualStrings("ai", diag.section);
    try expectEqualStrings("provider", diag.key);
}

// --- Provider mode parsing -------------------------------------------------
// The deterministic-advisory quartet (provider.run/Request/Advisory/
// deterministicAdvisory) was removed as production-dead -- the command engines
// emit richer typed JSON. Only the provider Mode enum and its name conversions
// remain, so this covers that surviving surface.

test "provider mode name round-trips and rejects unknown names" {
    inline for ([_]provider.Mode{ .disabled, .stub, .local, .remote }) |mode| {
        const name = provider.modeName(mode);
        try expectEqual(mode, provider.modeFromName(name).?);
    }
    try expectEqualStrings("stub", provider.modeName(.stub));
    try expectEqualStrings("remote", provider.modeName(.remote));
    try std.testing.expect(provider.modeFromName("nope") == null);
    try std.testing.expect(provider.modeFromName("") == null);
}

// --- Path normalization + field redaction primitives (audit F-4) --

test "normalizeAbsolutePaths replaces absolute paths but preserves relative paths and division" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // An absolute multi-segment path (which can embed a secret segment) becomes a
    // placeholder; an embedded one is replaced in place.
    const abs = try redaction.normalizeAbsolutePaths(a, "/Users/dev/secret/calc.zig");
    try expect(abs.changed);
    try expectEqualStrings("<path>", abs.text);
    const emb = try redaction.normalizeAbsolutePaths(a, "see /etc/ssh/key here");
    try expect(emb.changed);
    try expectEqualStrings("see <path> here", emb.text);

    // A relative path and a lone division operator stay intact so the AI still
    // sees the mutated code.
    const rel = try redaction.normalizeAbsolutePaths(a, "src/calc.zig");
    try expect(!rel.changed);
    try expectEqualStrings("src/calc.zig", rel.text);
    const div = try redaction.normalizeAbsolutePaths(a, "const q = a / b;");
    try expect(!div.changed);
    try expectEqualStrings("const q = a / b;", div.text);
}

test "normalizeAbsolutePaths handles paths with spaces and Windows absolute paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const spaced = try redaction.normalizeAbsolutePaths(a, "panic at \"/Users/dev/My Project/src/main.zig:7:3\"");
    try expect(spaced.changed);
    try expectEqualStrings("panic at \"<path>\"", spaced.text);

    const unquoted = try redaction.normalizeAbsolutePaths(a, "panic at /Users/dev/My Project/src/main.zig:7:3");
    try expect(unquoted.changed);
    try expectEqualStrings("panic at <path>", unquoted.text);

    const windows = try redaction.normalizeAbsolutePaths(a, "panic at C:\\Users\\dev\\My Project\\src\\main.zig:7:3");
    try expect(windows.changed);
    try expectEqualStrings("panic at <path>", windows.text);
}

test "normalizeAbsolutePaths preserves Zig // and /// comment markers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A `//`-led run is a Zig comment, not an absolute path (a real absolute path
    // has a non-empty first segment, `/a/...`). Collapsing `//` to `<path>` would
    // corrupt the mutated code shown to the AI AND falsely flip `changed`, which
    // injects a bogus `absolute_path` entry into privacy.redactions_applied.
    const line = try redaction.normalizeAbsolutePaths(a, "// boundary off-by-one");
    try expect(!line.changed);
    try expectEqualStrings("// boundary off-by-one", line.text);

    const doc = try redaction.normalizeAbsolutePaths(a, "/// doc comment for f");
    try expect(!doc.changed);
    try expectEqualStrings("/// doc comment for f", doc.text);

    // A trailing comment plus a real absolute path on one line: the comment marker
    // stays verbatim, only the genuine path is redacted.
    const mixed = try redaction.normalizeAbsolutePaths(a, "const x = 1; // see /etc/ssh/key");
    try expect(mixed.changed);
    try expectEqualStrings("const x = 1; // see <path>", mixed.text);
}

test "normalizeAbsolutePaths redacts colon/scheme-prefixed absolute paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A `file://` URI -- which Zig/LLVM and build tooling emit in diagnostics --
    // must have its absolute path redacted, not left verbatim, so a developer/home
    // path never reaches a provider (the `:`-precedes-`/` rule used to suppress it).
    const uri = try redaction.normalizeAbsolutePaths(a, "see file:///Users/dev/secret/leak.zig");
    try expect(uri.changed);
    try expectEqualStrings("see file:<path>", uri.text);

    // A `label:/abs/path` form (path glued to a preceding `:`).
    const labeled = try redaction.normalizeAbsolutePaths(a, "note:/Users/dev/secret/leak.zig more");
    try expect(labeled.changed);
    try expectEqualStrings("note:<path> more", labeled.text);

    // An identifier glued to the path via a colon.
    const glued = try redaction.normalizeAbsolutePaths(a, "@import:/Users/dev/secret/leak.zig");
    try expect(glued.changed);
    try expectEqualStrings("@import:<path>", glued.text);
}

test "normalizeAbsolutePaths redacts single-segment absolute paths inside quotes and home-directory paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Regression: a short single-segment absolute path (`/root`, `/tmp`, `/etc`)
    // inside a quoted string value (the realistic leak vector for fields like
    // command.cwd / mutant.file) used to pass redaction verbatim because the
    // matcher required a second slash.
    const cwd = try redaction.normalizeAbsolutePaths(a, "\"cwd\": \"/root\"");
    try expect(cwd.changed);
    try expectEqualStrings("\"cwd\": \"<path>\"", cwd.text);
    const tmp = try redaction.normalizeAbsolutePaths(a, "\"file\": \"/tmp\"");
    try expect(tmp.changed);
    try expectEqualStrings("\"file\": \"<path>\"", tmp.text);

    // A `~`-prefixed home path is redacted from the `~` (previously leaked as
    // `~<path>`).
    const home = try redaction.normalizeAbsolutePaths(a, "see ~/.aws/credentials here");
    try expect(home.changed);
    try expectEqualStrings("see <path> here", home.text);

    // The unquoted division operator is still preserved (no second slash, not
    // quoted), so the AI still sees the mutated code.
    const div = try redaction.normalizeAbsolutePaths(a, "const q = a / b;");
    try expect(!div.changed);
    try expectEqualStrings("const q = a / b;", div.text);
}

test "redactField normalizes paths, scrubs secret values, and logs both kinds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // An absolute path with a secret segment: the whole path (secret included) is
    // normalized to <path> and the normalization is recorded.
    var log = context.RedactionLog.init(a);
    const out = try context.redactField(a, "/Users/dev/ghp_abcdefghijklmnopqrstuvwxyz0123/x.zig", &.{}, &log);
    try expect(std.mem.indexOf(u8, out, "/Users/") == null);
    try expect(std.mem.indexOf(u8, out, "ghp_abcdefghij") == null);
    try expect(hasLabel(log.applied(), context.label_absolute_path));

    // A bare secret token (no path) is scrubbed and recorded as secret_value, even
    // with no configured patterns -- the built-in value matchers always run.
    var log2 = context.RedactionLog.init(a);
    const out2 = try context.redactField(a, "key=ghp_abcdefghijklmnopqrstuvwxyz0123", &.{}, &log2);
    try expect(std.mem.indexOf(u8, out2, "ghp_abcdefghij") == null);
    try expect(hasLabel(log2.applied(), context.label_secret_value));
}

fn hasLabel(labels: []const []const u8, want: []const u8) bool {
    for (labels) |l| {
        if (std.mem.eql(u8, l, want)) return true;
    }
    return false;
}
