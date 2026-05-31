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

// --- Deterministic stub provider -------------------------------------------

test "the stub provider is deterministic and disabled mode yields no advisory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const req = provider.Request{ .flow = "explain", .mutant_id = "m_abc123", .operator = "arithmetic_add_sub" };

    const first = try provider.run(a, .stub, false, req);
    const second = try provider.run(a, .stub, false, req);
    try expectEqualStrings(first.advice, second.advice); // same context -> same advisory
    try expectEqualStrings("stub", first.provider_mode);
    try expectEqualStrings("explain", first.flow);

    try expectError(error.ProviderDisabled, provider.run(a, .disabled, false, req));
    try expectError(error.RemoteNotAllowed, provider.run(a, .remote, false, req));
}
