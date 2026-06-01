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
