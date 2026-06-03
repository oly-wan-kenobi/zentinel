const std = @import("std");
const zentinel = @import("zentinel");

const dc = zentinel.ai.doctest_command;
const command = zentinel.ai.command;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const report_snapshot = @embedFile("fixtures/ai/doctest/report.json");

fn parseValue(arena: std.mem.Allocator, source: []const u8) std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, arena, source, .{}) catch unreachable;
}

fn settings() command.Settings {
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

fn baseInput(flow: dc.Flow) dc.Input {
    return .{
        .flow = flow,
        .case_ref = null,
        .doc_path = null,
        .doc_exists = false,
        .provider_override = .stub,
        .report_json = report_snapshot,
        .settings = settings(),
    };
}

// --- Provider option behavior (docs/CLI_SPEC.md) ---------------------------

test "doctest AI --ai-provider remote without remote_allowed is ZNTL_AI_PROVIDER_NOT_ALLOWED" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var input = baseInput(.explain_doctest_failure);
    input.case_ref = "dt_01hr7p6h0v2fj3drdzt9k2a0xe";
    input.provider_override = .remote;
    try expectError(error.AiProviderNotAllowed, dc.run(arena, input, .json));
}

test "doctest AI --ai-provider disabled is ZNTL_AI_DISABLED" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var input = baseInput(.explain_doctest_failure);
    input.case_ref = "dt_01hr7p6h0v2fj3drdzt9k2a0xe";
    input.provider_override = .disabled;
    try expectError(error.AiDisabled, dc.run(arena, input, .json));
}

// --- required positional is a usage error, not a downstream AI failure (L32) ---

test "doctest AI subcommands reject a missing required positional as a usage error (L32)" {
    // suggest needs <doc-path>; explain and review-snapshot need <case-ref>. A
    // missing positional must surface this exact CLI usage detail (rendered as
    // ZNTL_CLI_INVALID_OPTION) instead of being forwarded as a null ref the engine
    // reports as the opaque ZNTL_DOCTEST_{DOC,CASE}_NOT_FOUND.
    try expectEqualStrings("missing <doc-path>", dc.missingPositional(.suggest_doctest, null).?);
    try expectEqualStrings("missing <case-ref>", dc.missingPositional(.explain_doctest_failure, null).?);
    try expectEqualStrings("missing <case-ref>", dc.missingPositional(.review_snapshot, null).?);
    // suggest-missing takes its target via --file, so it requires no positional.
    try expect(dc.missingPositional(.suggest_missing_doctests, null) == null);
    // A present positional satisfies every flow (no over-rejection).
    try expect(dc.missingPositional(.suggest_doctest, "docs/CONFIG_SPEC.md") == null);
    try expect(dc.missingPositional(.explain_doctest_failure, "dt_01hr7p6h0v2fj3drdzt9k2a0xe") == null);
    try expect(dc.missingPositional(.review_snapshot, "dt_01hr7p6h0v2fj3drdzt9k2a0xe") == null);
}

// --- review-snapshot requires snapshot evidence ----------------------------

test "review-snapshot on a case without snapshot evidence is ZNTL_DOCTEST_CASE_NOT_FOUND" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var input = baseInput(.review_snapshot);
    // The passed config case (display 2) has snapshot: null.
    input.case_ref = "dt_01hr7p6h0v2fj3drdzt9k2a0yf";
    try expectError(error.DoctestCaseNotFound, dc.run(arena, input, .json));
}

// --- suggest with optional --input-report context --------------------------

test "suggest accepts an optional report as context and still produces a suggestion" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.run(arena, .{
        .flow = .suggest_doctest,
        .case_ref = null,
        .doc_path = "docs/CONFIG_SPEC.md",
        .doc_exists = true,
        .provider_override = .stub,
        .report_json = report_snapshot, // optional context, must be tolerated
        .settings = settings(),
    }, .json);
    try expectEqual(@as(u8, 0), out.exit_code);
    try expectEqual(dc.ResponseViolation.ok, dc.validateSuggestResponse(parseValue(arena, out.body)));
}

// --- text rendering --------------------------------------------------------

test "explain text format renders advisory lines" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var input = baseInput(.explain_doctest_failure);
    input.case_ref = "dt_01hr7p6h0v2fj3drdzt9k2a0xe";
    const out = try dc.run(arena, input, .text);
    try expectEqual(@as(u8, 0), out.exit_code);
    try expect(std.mem.indexOf(u8, out.body, "classification: doctest_output_mismatch") != null);
    try expect(std.mem.indexOf(u8, out.body, "next action:") != null);
}

// --- advisory-only: AI cannot update expected output or doctest status ------

test "a doctest suggest response that tries to set doctest status is rejected" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const tampered = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.doctest.suggest.response.v1",
        \\  "suggestions": [ {"target_file":"docs/CONFIG_SPEC.md","line_hint":null,"reason":"r","block":"x"} ],
        \\  "status": "passed" }
    );
    try expectEqual(dc.ResponseViolation.unknown_field, dc.validateSuggestResponse(tampered));
}

test "a snapshot-review response that approves an update is rejected" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const tampered = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.doctest.snapshot_review.response.v1", "classification": "wording_change",
        \\  "summary": "s", "risk": "low", "evidence_refs": [], "next_action": "n", "apply_update": true }
    );
    try expectEqual(dc.ResponseViolation.unknown_field, dc.validateSnapshotReviewResponse(tampered));
}

// --- suggest-missing without a report --------------------------------------

test "suggest-missing works without a report and only suggests, never edits" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.run(arena, .{
        .flow = .suggest_missing_doctests,
        .case_ref = null,
        .doc_path = "docs/REPORT_SCHEMA.md",
        .doc_exists = true,
        .provider_override = .stub,
        .report_json = null,
        .settings = settings(),
    }, .json);
    try expectEqual(@as(u8, 0), out.exit_code);
    const value = parseValue(arena, out.body);
    try expectEqual(dc.ResponseViolation.ok, dc.validateSuggestResponse(value));
    // The only output is advisory suggestions; there is no status or apply field.
    try expect(value.object.get("status") == null);
}
