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
