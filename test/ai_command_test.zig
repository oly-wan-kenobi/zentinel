const std = @import("std");
const zentinel = @import("zentinel");

const command = zentinel.ai.command;
const doctest_command = zentinel.ai.doctest_command;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;

// A known-good mutation report so the in-range regression case proves the bounds
// check does not reject valid integers.
const good_report = @embedFile("fixtures/ai/commands/report.json");

fn stubSettings() command.Settings {
    return .{
        .ai_enabled = true,
        .config_mode = .stub,
        .remote_allowed = false,
        .redact_patterns = &command.default_redact_patterns,
        .project_name = "example",
        .zig_version = "0.16.0",
        .zentinel_version = "0.0.0",
    };
}

// --- Out-of-range / non-integer report integers (task 107) ------------------
//
// `--input-report` is untrusted. A report-sourced integer above u32 used to
// panic the process via an unchecked `@intCast` to u32 (abort / exit 134 in
// Debug and ReleaseSafe, silent truncation in ReleaseFast). The AI surface must
// instead reject it with a clean `ZNTL_AI_*` failure and a non-abnormal exit.

test "explain rejects an out-of-range report integer instead of panicking" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // span.line_start and display_id both exceed maxInt(u32) (2^32 + 1). The
    // mutant resolves by its durable id, so resolution does not depend on the
    // out-of-range display_id; the narrowing happens while building the context.
    const malicious =
        \\{
        \\  "mutants": [
        \\    {
        \\      "id": "m_overflow",
        \\      "display_id": 4294967297,
        \\      "operator": "arithmetic_add_sub",
        \\      "file": "src/x.zig",
        \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 4294967297, "column_start": 1, "line_end": 1, "column_end": 2 },
        \\      "result": { "status": "survived", "mode": "Debug", "evidence": {} }
        \\    }
        \\  ]
        \\}
    ;
    const input = command.Input{
        .flow = .explain,
        .mutant_ref = "m_overflow",
        .provider_override = null,
        .report_json = malicious,
        .settings = stubSettings(),
    };
    // A clean invalid-report failure, never a panic (which would abort the test
    // process with exit 134 before this assertion is reached).
    try expectError(error.AiReportNotFound, command.run(a, input, .json));
}

test "explain rejects a non-integer report integer instead of treating it as zero" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // display_id is a string where an integer is required.
    const malicious =
        \\{
        \\  "mutants": [
        \\    {
        \\      "id": "m_badtype",
        \\      "display_id": "not-a-number",
        \\      "operator": "arithmetic_add_sub",
        \\      "file": "src/x.zig",
        \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
        \\      "result": { "status": "survived", "mode": "Debug", "evidence": {} }
        \\    }
        \\  ]
        \\}
    ;
    const input = command.Input{
        .flow = .explain,
        .mutant_ref = "m_badtype",
        .provider_override = null,
        .report_json = malicious,
        .settings = stubSettings(),
    };
    try expectError(error.AiReportNotFound, command.run(a, input, .json));
}

test "review-tests redacts secret-shaped report ids before echoing them into clusters (F-4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Untrusted report whose survivor id embeds a GitHub-token-shaped secret. The
    // `m_` prefix passes response validation, but the secret must not reach the
    // rendered review output (the leak this stub previously had).
    const leaky =
        \\{
        \\  "mutants": [
        \\    {
        \\      "id": "m_ghp_abcdefghijklmnopqrstuvwxyz0123",
        \\      "display_id": 1,
        \\      "operator": "comparison_boundary",
        \\      "backend": "ast",
        \\      "backend_stability": "stable",
        \\      "operator_stability": "stable",
        \\      "file": "src/x.zig",
        \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
        \\      "original": "a < b",
        \\      "replacement": "a <= b",
        \\      "diff": ["-a < b", "+a <= b"],
        \\      "expected_compile": "compiles",
        \\      "result": {
        \\        "status": "survived",
        \\        "mode": "Debug",
        \\        "commands": [
        \\          {
        \\            "command": { "original": "zig test src/x.zig", "argv": ["zig", "test", "src/x.zig"], "cwd": ".", "environment_policy": "minimal", "shell": false },
        \\            "phase": "mutant",
        \\            "status": "passed",
        \\            "exit_code": 0,
        \\            "timed_out": false,
        \\            "failure_kind": "none",
        \\            "duration_ms": 0,
        \\            "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" },
        \\            "skip_reason": null
        \\          }
        \\        ],
        \\        "evidence": {}
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    const input = command.Input{
        .flow = .review_tests,
        .mutant_ref = null,
        .provider_override = null,
        .report_json = leaky,
        .settings = stubSettings(),
    };
    const outcome = try command.run(a, input, .json);
    try expectEqual(@as(u8, 0), outcome.exit_code);
    // The secret is gone; a redacted id (m_ prefix preserved) remains.
    try expect(std.mem.indexOf(u8, outcome.body, github_secret) == null);
    try expect(std.mem.indexOf(u8, outcome.body, "m_") != null);
}

test "explain still succeeds on a valid in-range report" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const input = command.Input{
        .flow = .explain,
        .mutant_ref = "1",
        .provider_override = null,
        .report_json = good_report,
        .settings = stubSettings(),
    };
    const outcome = try command.run(a, input, .json);
    try expectEqual(@as(u8, 0), outcome.exit_code);
    try expect(outcome.body.len > 0);
}

// --- AI context redaction scope (task 120, audit F-4) -----------------------
//
// Redaction was wired only to evidence excerpts; the source-, diff-, and
// path-bearing context fields (mutant.file/original/replacement/diff) passed
// through verbatim, and privacy.redactions_applied was always empty. A report
// whose file is an absolute developer path and whose source/diff carries a
// secret-looking token must not leak either into the built context or the
// rendered output, and redactions_applied must record what was scrubbed.

const abs_path_secret = "/Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123/calc.zig";
const github_secret = "ghp_abcdefghijklmnopqrstuvwxyz0123";

const leaky_report =
    \\{
    \\  "mutants": [
    \\    {
    \\      "id": "m_leak",
    \\      "display_id": 1,
    \\      "operator": "arithmetic_add_sub",
    \\      "backend": "ast",
    \\      "backend_stability": "stable",
    \\      "operator_stability": "stable",
    \\      "file": "/Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123/calc.zig",
    \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
    \\      "original": "const token = \"ghp_abcdefghijklmnopqrstuvwxyz0123\";",
    \\      "replacement": "const token = \"x\";",
    \\      "diff": ["-const token = \"ghp_abcdefghijklmnopqrstuvwxyz0123\";", "+const token = \"x\";"],
    \\      "expected_compile": "compiles",
    \\      "result": {
    \\        "status": "survived",
    \\        "mode": "Debug",
    \\        "commands": [
    \\          {
    \\            "command": {
    \\              "original": "zig test /Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123/calc.zig",
    \\              "argv": ["zig", "test", "/Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123/calc.zig"],
    \\              "cwd": "/Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123",
    \\              "environment_policy": "minimal",
    \\              "shell": false
    \\            },
    \\            "phase": "mutant",
    \\            "status": "passed",
    \\            "exit_code": 0,
    \\            "timed_out": false,
    \\            "failure_kind": "none",
    \\            "duration_ms": 0,
    \\            "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" },
    \\            "skip_reason": null
    \\          }
    \\        ],
    \\        "evidence": {}
    \\      }
    \\    }
    \\  ]
    \\}
;

test "explain context redacts absolute paths and secret tokens in every field (F-4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const report = try std.json.parseFromSliceLeaky(std.json.Value, a, leaky_report, .{});
    const mutant = report.object.get("mutants").?.array.items[0];
    const prompt = try command.buildPromptValue(a, .explain, .stub, mutant, report, stubSettings());
    const json = try std.json.Stringify.valueAlloc(a, prompt, .{ .whitespace = .indent_2 });

    // Neither the absolute path nor the secret token survives into the context.
    try expect(std.mem.indexOf(u8, json, abs_path_secret) == null);
    try expect(std.mem.indexOf(u8, json, github_secret) == null);
    try expect(std.mem.indexOf(u8, json, "/Users/") == null);
    // redactions_applied is populated (not the always-empty list it used to be).
    try expect(std.mem.indexOf(u8, json, "\"redactions_applied\": []") == null);
    try expect(std.mem.indexOf(u8, json, "absolute_path") != null);
    try expect(std.mem.indexOf(u8, json, "secret_value") != null);
}

test "ai.source_context_lines flows into the context window before_lines/after_lines (L43)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const report = try std.json.parseFromSliceLeaky(std.json.Value, a, leaky_report, .{});
    const mutant = report.object.get("mutants").?.array.items[0];

    // The configured source-context window (docs/CONFIG_SPEC: "Lines before/after
    // mutant for prompts") now reaches the built AI context instead of being a
    // hardcoded 0; the privacy policy stays "none" so no source snippet is sent.
    var settings = stubSettings();
    settings.source_context_lines = 20;
    const prompt = try command.buildPromptValue(a, .explain, .stub, mutant, report, settings);
    const sc = prompt.object.get("context").?.object.get("source_context").?.object;
    try expectEqual(@as(i64, 20), sc.get("before_lines").?.integer);
    try expectEqual(@as(i64, 20), sc.get("after_lines").?.integer);
    try std.testing.expectEqualStrings("none", sc.get("policy").?.string); // privacy unchanged: snippet omitted
    try expectEqual(@as(usize, 0), sc.get("snippet").?.array.items.len);

    // The default window (4) flows through too, rather than the old hardcoded 0.
    const dflt = try command.buildPromptValue(a, .explain, .stub, mutant, report, stubSettings());
    const sc2 = dflt.object.get("context").?.object.get("source_context").?.object;
    try expectEqual(@as(i64, 4), sc2.get("before_lines").?.integer);
    try expectEqual(@as(i64, 4), sc2.get("after_lines").?.integer);
}

// A report whose ONLY poisoned fields are the mutant id (an absolute path) and
// operator (an Anthropic-key-shaped token); every other field is clean, so any
// surviving secret in the output came specifically through id/operator (M9).
const id_operator_leak_report =
    \\{
    \\  "run": { "zig_version": "0.16.0", "zentinel_version": "0.0.0" },
    \\  "mutants": [
    \\    {
    \\      "id": "/Users/victim/.aws/credentials",
    \\      "display_id": 1,
    \\      "operator": "sk-ant-api03-LEAKEDSECRET01234567",
    \\      "backend": "ast",
    \\      "backend_stability": "stable",
    \\      "operator_stability": "stable",
    \\      "file": "src/calc.zig",
    \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
    \\      "original": "a",
    \\      "replacement": "b",
    \\      "diff": [],
    \\      "expected_compile": "compiles",
    \\      "result": {
    \\        "status": "survived",
    \\        "mode": "Debug",
    \\        "commands": [
    \\          {
    \\            "command": { "original": "zig build test", "argv": ["zig", "build", "test"], "cwd": ".", "environment_policy": "minimal", "shell": false },
    \\            "phase": "mutant", "status": "passed", "exit_code": 0, "timed_out": false, "failure_kind": "none", "duration_ms": 0,
    \\            "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" }, "skip_reason": null
    \\          }
    \\        ],
    \\        "evidence": {}
    \\      }
    \\    }
    \\  ]
    \\}
;

test "explain redacts secrets in the report mutant id and operator (M9)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const report = try std.json.parseFromSliceLeaky(std.json.Value, a, id_operator_leak_report, .{});
    const mutant = report.object.get("mutants").?.array.items[0];

    // (1) The prompt context serialized to the provider must not carry the raw
    //     absolute path (from id) or the secret token (from operator).
    const prompt = try command.buildPromptValue(a, .explain, .stub, mutant, report, stubSettings());
    const ctx_json = try std.json.Stringify.valueAlloc(a, prompt, .{ .whitespace = .indent_2 });
    try expect(std.mem.indexOf(u8, ctx_json, "/Users/victim") == null);
    try expect(std.mem.indexOf(u8, ctx_json, "sk-ant-api03-LEAKEDSECRET01234567") == null);

    // (2) The deterministic stub advisory rendered to stdout must not leak them
    //     either (it echoes id/operator into its summary).
    const input = command.Input{
        .flow = .explain,
        .mutant_ref = "1",
        .provider_override = null,
        .report_json = id_operator_leak_report,
        .settings = stubSettings(),
    };
    const outcome = try command.run(a, input, .json);
    try expect(std.mem.indexOf(u8, outcome.body, "/Users/victim") == null);
    try expect(std.mem.indexOf(u8, outcome.body, "sk-ant-api03-LEAKEDSECRET01234567") == null);
}

// A report whose ONLY poisoned field is test_selection.strategy — an absolute
// path glued to an Anthropic-key-shaped secret. On the read side of an untrusted
// `--input-report`, strategy is parsed as a raw JSON string (not the typed
// Strategy enum), so any surviving secret in the context.test_context.selection_reason
// came specifically through that field (L29).
const selection_leak_report =
    \\{
    \\  "run": { "zig_version": "0.16.0", "zentinel_version": "0.0.0" },
    \\  "mutants": [
    \\    {
    \\      "id": "m_sel",
    \\      "display_id": 1,
    \\      "operator": "arithmetic_add_sub",
    \\      "backend": "ast",
    \\      "backend_stability": "stable",
    \\      "operator_stability": "stable",
    \\      "file": "src/calc.zig",
    \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
    \\      "original": "a",
    \\      "replacement": "b",
    \\      "diff": [],
    \\      "expected_compile": "compiles",
    \\      "test_selection": { "strategy": "/Users/victim/.aws/credentials sk-ant-api03-LEAKEDSECRET01234567" },
    \\      "result": {
    \\        "status": "survived",
    \\        "mode": "Debug",
    \\        "commands": [
    \\          {
    \\            "command": { "original": "zig build test", "argv": ["zig", "build", "test"], "cwd": ".", "environment_policy": "minimal", "shell": false },
    \\            "phase": "mutant", "status": "passed", "exit_code": 0, "timed_out": false, "failure_kind": "none", "duration_ms": 0,
    \\            "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" }, "skip_reason": null
    \\          }
    \\        ],
    \\        "evidence": {}
    \\      }
    \\    }
    \\  ]
    \\}
;

test "explain context redacts secrets in test_selection.strategy (selection_reason) (L29)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const report = try std.json.parseFromSliceLeaky(std.json.Value, a, selection_leak_report, .{});
    const mutant = report.object.get("mutants").?.array.items[0];
    const prompt = try command.buildPromptValue(a, .explain, .stub, mutant, report, stubSettings());

    // The selection_reason field carries the redacted, not the raw, strategy:
    // the absolute path collapses to <path> and the secret to [REDACTED].
    const ctx = prompt.object.get("context").?;
    const selection_reason = ctx.object.get("test_context").?.object.get("selection_reason").?.string;
    try std.testing.expectEqualStrings("<path> [REDACTED]", selection_reason);

    // Neither the raw path nor the raw secret survives anywhere in the context,
    // and redactions_applied records both scrubs (the privacy contract must not
    // claim the leak did not happen).
    const ctx_json = try std.json.Stringify.valueAlloc(a, prompt, .{ .whitespace = .indent_2 });
    try expect(std.mem.indexOf(u8, ctx_json, "/Users/victim") == null);
    try expect(std.mem.indexOf(u8, ctx_json, "sk-ant-api03-LEAKEDSECRET01234567") == null);
    try expect(std.mem.indexOf(u8, ctx_json, "\"redactions_applied\": []") == null);
    try expect(std.mem.indexOf(u8, ctx_json, "absolute_path") != null);
    try expect(std.mem.indexOf(u8, ctx_json, "secret_value") != null);
}

test "explain context preserves report command arrays instead of fabricating zig build test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const command_report =
        \\{
        \\  "run": { "zig_version": "0.16.0", "zentinel_version": "0.0.0" },
        \\  "baseline": { "status": "passed" },
        \\  "mutants": [
        \\    {
        \\      "id": "m_cmd",
        \\      "display_id": 1,
        \\      "operator": "arithmetic_add_sub",
        \\      "backend": "ast",
        \\      "backend_stability": "stable",
        \\      "operator_stability": "stable",
        \\      "file": "src/calc.zig",
        \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
        \\      "original": "+",
        \\      "replacement": "-",
        \\      "diff": ["-a + b", "+a - b"],
        \\      "expected_compile": "compiles",
        \\      "result": {
        \\        "status": "survived",
        \\        "mode": "Debug",
        \\        "commands": [
        \\          {
        \\            "command": {
        \\              "original": "zig test src/custom.zig --test-filter add",
        \\              "argv": ["zig", "test", "src/custom.zig", "--test-filter", "add"],
        \\              "cwd": "<project>",
        \\              "environment_policy": "minimal",
        \\              "shell": false
        \\            },
        \\            "phase": "mutant",
        \\            "status": "passed",
        \\            "exit_code": 0,
        \\            "timed_out": false,
        \\            "failure_kind": "none",
        \\            "duration_ms": 12,
        \\            "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" },
        \\            "skip_reason": null
        \\          }
        \\        ],
        \\        "phase": "mutant",
        \\        "duration_ms": 12,
        \\        "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" },
        \\        "skip_reason": null
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, command_report, .{});
    const mutant = parsed.object.get("mutants").?.array.items[0];
    const prompt = try command.buildPromptValue(a, .explain, .stub, mutant, parsed, stubSettings());
    const json = try std.json.Stringify.valueAlloc(a, prompt, .{ .whitespace = .indent_2 });

    try expect(std.mem.indexOf(u8, json, "zig test src/custom.zig --test-filter add") != null);
    try expect(std.mem.indexOf(u8, json, "\"--test-filter\"") != null);
    try expect(std.mem.indexOf(u8, json, "zig build test") == null);
}

test "explain rejects mutants without structured command evidence instead of fabricating defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const missing_command_report =
        \\{
        \\  "run": { "zig_version": "0.16.0", "zentinel_version": "0.0.0" },
        \\  "baseline": { "status": "passed" },
        \\  "mutants": [
        \\    {
        \\      "id": "m_missing_cmd",
        \\      "display_id": 1,
        \\      "operator": "arithmetic_add_sub",
        \\      "backend": "ast",
        \\      "backend_stability": "stable",
        \\      "operator_stability": "stable",
        \\      "file": "src/calc.zig",
        \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
        \\      "original": "+",
        \\      "replacement": "-",
        \\      "diff": ["-a + b", "+a - b"],
        \\      "expected_compile": "compiles",
        \\      "result": {
        \\        "status": "survived",
        \\        "mode": "Debug",
        \\        "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" },
        \\        "skip_reason": null
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, missing_command_report, .{});
    const mutant = parsed.object.get("mutants").?.array.items[0];
    try expectError(error.AiReportNotFound, command.buildPromptValue(a, .explain, .stub, mutant, parsed, stubSettings()));
}

test "explain rejects partial command result evidence instead of defaulting fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const partial_command_report =
        \\{
        \\  "run": { "zig_version": "0.16.0", "zentinel_version": "0.0.0" },
        \\  "baseline": { "status": "passed" },
        \\  "mutants": [
        \\    {
        \\      "id": "m_partial_cmd",
        \\      "display_id": 1,
        \\      "operator": "arithmetic_add_sub",
        \\      "backend": "ast",
        \\      "backend_stability": "stable",
        \\      "operator_stability": "stable",
        \\      "file": "src/calc.zig",
        \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
        \\      "original": "+",
        \\      "replacement": "-",
        \\      "diff": ["-a + b", "+a - b"],
        \\      "expected_compile": "compiles",
        \\      "result": {
        \\        "status": "survived",
        \\        "mode": "Debug",
        \\        "commands": [
        \\          {
        \\            "command": {
        \\              "original": "zig test src/custom.zig",
        \\              "argv": ["zig", "test", "src/custom.zig"],
        \\              "cwd": "<project>"
        \\            },
        \\            "exit_code": 0,
        \\            "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" }
        \\          }
        \\        ],
        \\        "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" }
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, partial_command_report, .{});
    const mutant = parsed.object.get("mutants").?.array.items[0];
    try expectError(error.AiReportNotFound, command.buildPromptValue(a, .explain, .stub, mutant, parsed, stubSettings()));
}

test "explain on an invalid (empty-commands) mutant builds context instead of reporting report-not-found (L1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // An `invalid` mutant legitimately ran no command, so a real report serializes
    // `"commands": []`. The report was found and the ref resolved, so explain must
    // build a context describing why it did not run -- not fail with the
    // misleading AiReportNotFound (L1).
    const invalid_mutant_report =
        \\{
        \\  "run": { "zig_version": "0.16.0", "zentinel_version": "0.0.0" },
        \\  "baseline": { "status": "passed" },
        \\  "mutants": [
        \\    {
        \\      "id": "m_invalid",
        \\      "display_id": 1,
        \\      "operator": "comparison_boundary",
        \\      "backend": "ast",
        \\      "backend_stability": "stable",
        \\      "operator_stability": "stable",
        \\      "file": "src/x.zig",
        \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
        \\      "original": "a",
        \\      "replacement": "b",
        \\      "diff": [],
        \\      "expected_compile": "compiles",
        \\      "result": {
        \\        "status": "invalid",
        \\        "mode": "Debug",
        \\        "commands": [],
        \\        "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "sandbox: patch out of range" },
        \\        "skip_reason": null
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, invalid_mutant_report, .{});
    const mutant = parsed.object.get("mutants").?.array.items[0];
    const prompt = try command.buildPromptValue(a, .explain, .stub, mutant, parsed, stubSettings());
    const json = try std.json.Stringify.valueAlloc(a, prompt, .{ .whitespace = .indent_2 });
    // The context carries the empty command set and the mutant's invalid status.
    try expect(std.mem.indexOf(u8, json, "\"commands\": []") != null);
    try expect(std.mem.indexOf(u8, json, "\"status\": \"invalid\"") != null);
}

test "explain context redacts project metadata before it reaches the prompt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const project_secret = "ghp_projectmetadataabcdefghijklmnopqr";
    const report_with_project_metadata =
        \\{
        \\  "run": { "zig_version": "/Users/dev/zig-ghp_projectmetadataabcdefghijklmnopqr/0.16.0", "zentinel_version": "0.0.0-ghp_projectmetadataabcdefghijklmnopqr" },
        \\  "baseline": { "status": "passed" },
        \\  "mutants": [
        \\    {
        \\      "id": "m_project_meta",
        \\      "display_id": 1,
        \\      "operator": "arithmetic_add_sub",
        \\      "backend": "ast",
        \\      "backend_stability": "stable",
        \\      "operator_stability": "stable",
        \\      "file": "src/calc.zig",
        \\      "span": { "byte_start": 0, "byte_end": 1, "line_start": 1, "column_start": 1, "line_end": 1, "column_end": 2 },
        \\      "original": "+",
        \\      "replacement": "-",
        \\      "diff": ["-a + b", "+a - b"],
        \\      "expected_compile": "compiles",
        \\      "result": {
        \\        "status": "survived",
        \\        "mode": "Debug",
        \\        "commands": [
        \\          {
        \\            "command": {
        \\              "original": "zig test src/calc.zig",
        \\              "argv": ["zig", "test", "src/calc.zig"],
        \\              "cwd": "<project>",
        \\              "environment_policy": "minimal",
        \\              "shell": false
        \\            },
        \\            "phase": "mutant",
        \\            "status": "passed",
        \\            "exit_code": 0,
        \\            "timed_out": false,
        \\            "failure_kind": "none",
        \\            "duration_ms": 12,
        \\            "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" },
        \\            "skip_reason": null
        \\          }
        \\        ],
        \\        "evidence": { "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "" },
        \\        "skip_reason": null
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    var settings = stubSettings();
    settings.project_name = project_secret;
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, report_with_project_metadata, .{});
    const mutant = parsed.object.get("mutants").?.array.items[0];
    const prompt = try command.buildPromptValue(a, .explain, .stub, mutant, parsed, settings);
    const json = try std.json.Stringify.valueAlloc(a, prompt, .{ .whitespace = .indent_2 });

    try expect(std.mem.indexOf(u8, json, project_secret) == null);
    try expect(std.mem.indexOf(u8, json, "/Users/") == null);
    try expect(std.mem.indexOf(u8, json, "[REDACTED]") != null);
    try expect(std.mem.indexOf(u8, json, "<path>") != null);
}

test "explain rendered output no longer echoes absolute paths or secret tokens (F-4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const input = command.Input{
        .flow = .explain,
        .mutant_ref = "m_leak",
        .provider_override = null,
        .report_json = leaky_report,
        .settings = stubSettings(),
    };
    inline for (.{ .text, .json }) |fmt| {
        const outcome = try command.run(a, input, fmt);
        try expectEqual(@as(u8, 0), outcome.exit_code);
        try expect(std.mem.indexOf(u8, outcome.body, abs_path_secret) == null);
        try expect(std.mem.indexOf(u8, outcome.body, github_secret) == null);
        try expect(std.mem.indexOf(u8, outcome.body, "/Users/") == null);
    }
}

test "doctest explain rejects an out-of-range case line instead of panicking" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A doctest report case whose line_start exceeds maxInt(u32). The case
    // resolves by its durable id; the narrowing happens while building the
    // doctest context (optU32 over line_start).
    const malicious =
        \\{
        \\  "cases": [
        \\    {
        \\      "id": "dt_overflow",
        \\      "file": "docs/CLI.md",
        \\      "line_start": 4294967297,
        \\      "line_end": 4294967300,
        \\      "kind": "cli",
        \\      "status": "failed",
        \\      "result": { "failure_summary": "boom" }
        \\    }
        \\  ]
        \\}
    ;
    const input = doctest_command.Input{
        .flow = .explain_doctest_failure,
        .case_ref = "dt_overflow",
        .doc_path = null,
        .doc_exists = false,
        .provider_override = null,
        .report_json = malicious,
        .settings = stubSettings(),
    };
    try expectError(error.AiReportNotFound, doctest_command.run(a, input, .json));
}

test "doctest survivor context redacts absolute paths and secret tokens in every field (F-4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const survivor_case =
        \\{
        \\  "id": "dc_1",
        \\  "file": "/Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123/docs.md",
        \\  "source_ref": "/Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123/docs.md#ex",
        \\  "line_start": 1,
        \\  "line_end": 2,
        \\  "mutation": {
        \\    "survivor_ref": "ds_1",
        \\    "mutant_id": "m_1",
        \\    "operator": "arithmetic_add_sub",
        \\    "mutated_diff": ["-const k = \"ghp_abcdefghijklmnopqrstuvwxyz0123\";", "+const k = \"x\";"],
        \\    "runner_evidence": {
        \\      "status": "survived",
        \\      "command": {
        \\        "original": "zig test /Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123/docs.md",
        \\        "argv": ["zig", "test", "/Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123/docs.md"],
        \\        "cwd": "/Users/dev/work-ghp_abcdefghijklmnopqrstuvwxyz0123",
        \\        "environment_policy": "minimal",
        \\        "shell": false
        \\      },
        \\      "exit_code": 0,
        \\      "timed_out": false,
        \\      "failure_kind": "none",
        \\      "stdout_excerpt": "",
        \\      "stderr_excerpt": "",
        \\      "failure_summary": "",
        \\      "skip_reason": null
        \\    }
        \\  }
        \\}
    ;
    const case = try std.json.parseFromSliceLeaky(std.json.Value, a, survivor_case, .{});
    const ctx = try doctest_command.buildSurvivorContextValue(a, .stub, case, stubSettings());
    const json = try std.json.Stringify.valueAlloc(a, ctx, .{ .whitespace = .indent_2 });

    try expect(std.mem.indexOf(u8, json, github_secret) == null);
    try expect(std.mem.indexOf(u8, json, "/Users/") == null);
    try expect(std.mem.indexOf(u8, json, "\"redactions_applied\": []") == null);
}

fn sharedErr(r: command.SharedOptionResult) ?[]const u8 {
    return switch (r) {
        .err => |d| d,
        else => null,
    };
}

fn sharedTag(r: command.SharedOptionResult) std.meta.Tag(command.SharedOptionResult) {
    return std.meta.activeTag(r);
}

// The three AI command loops (runAiCommand / runDoctestAi / runDoctestSurvivorAi)
// now share this one parser, so its behavior IS their shared-option behavior. Pin
// every consumed/err/not_shared outcome and the exact error strings so a
// regression here is caught for all three commands at once (L16).
test "parseSharedOption parses each shared AI option with exact outcomes and error strings (L16)" {
    const expectEqualStrings = std.testing.expectEqualStrings;

    // --ai-provider <mode>: consumed, sets the mode, advances i onto the value.
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{ "--ai-provider", "stub" };
        try expect(sharedTag(command.parseSharedOption(&args, &i, &opts)) == .consumed);
        try expectEqual(command.Mode.stub, opts.provider_override.?);
        try expectEqual(@as(usize, 1), i);
    }
    // --ai-provider with no value, and with an invalid mode.
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{"--ai-provider"};
        try expectEqualStrings("--ai-provider requires a value", sharedErr(command.parseSharedOption(&args, &i, &opts)).?);
    }
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{ "--ai-provider", "bogus" };
        try expectEqualStrings("--ai-provider must be disabled|stub|local|remote", sharedErr(command.parseSharedOption(&args, &i, &opts)).?);
    }
    // --input-report <path>: consumed, sets the path; missing value errors.
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{ "--input-report", "out/report.json" };
        try expect(sharedTag(command.parseSharedOption(&args, &i, &opts)) == .consumed);
        try expectEqualStrings("out/report.json", opts.input_report.?);
    }
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{"--input-report"};
        try expectEqualStrings("--input-report requires a value", sharedErr(command.parseSharedOption(&args, &i, &opts)).?);
    }
    // --format text|json: consumed; an invalid value errors.
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{ "--format", "json" };
        try expect(sharedTag(command.parseSharedOption(&args, &i, &opts)) == .consumed);
        try expectEqual(command.Format.json, opts.format);
    }
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{ "--format", "yaml" };
        try expectEqualStrings("--format must be 'text' or 'json'", sharedErr(command.parseSharedOption(&args, &i, &opts)).?);
    }
    // A positional and a command-specific flag (--file) are both not_shared, with
    // i left untouched so the caller owns them.
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{ "m_x", "--format", "json" };
        try expect(sharedTag(command.parseSharedOption(&args, &i, &opts)) == .not_shared);
        try expectEqual(@as(usize, 0), i);
    }
    {
        var opts = command.SharedOptions{};
        var i: usize = 0;
        const args = [_][]const u8{"--file"};
        try expect(sharedTag(command.parseSharedOption(&args, &i, &opts)) == .not_shared);
    }
    // Defaults when no shared option is parsed.
    const def = command.SharedOptions{};
    try expectEqual(@as(?command.Mode, null), def.provider_override);
    try expectEqual(@as(?[]const u8, null), def.input_report);
    try expectEqual(command.Format.text, def.format);
}
