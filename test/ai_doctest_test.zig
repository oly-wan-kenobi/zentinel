const std = @import("std");
const zentinel = @import("zentinel");

const dc = zentinel.ai.doctest_command;
const command = zentinel.ai.command;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const report_snapshot = @embedFile("fixtures/ai/doctest/report.json");
const explain_snapshot = @embedFile("fixtures/ai/doctest/explain.stub.json");
const suggest_snapshot = @embedFile("fixtures/ai/doctest/suggest.stub.json");
const review_snapshot_fixture = @embedFile("fixtures/ai/doctest/review_snapshot.stub.json");
const missing_snapshot = @embedFile("fixtures/ai/doctest/suggest_missing.stub.json");

fn parseValue(arena: std.mem.Allocator, source: []const u8) std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, arena, source, .{}) catch unreachable;
}

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

// --- Defaults + flow naming ------------------------------------------------

test "doctest AI default report path matches the CLI contract" {
    try expectEqualStrings("zig-out/zentinel/doctest/report.json", dc.default_report_path);
}

test "doctest explain reuses the explain response schema; suggest/review use doctest schemas" {
    try expectEqualStrings("zentinel.ai.explain.response.v1", dc.responseSchemaName(.explain_doctest_failure));
    try expectEqualStrings("zentinel.ai.doctest.suggest.response.v1", dc.responseSchemaName(.suggest_doctest));
    try expectEqualStrings("zentinel.ai.doctest.snapshot_review.response.v1", dc.responseSchemaName(.review_snapshot));
    try expectEqualStrings("zentinel.ai.doctest.suggest.response.v1", dc.responseSchemaName(.suggest_missing_doctests));
}

test "doctest failure tokens map to documented codes" {
    try expectEqualStrings("ZNTL_DOCTEST_CASE_NOT_FOUND", dc.failureToken(error.DoctestCaseNotFound));
    try expectEqualStrings("ZNTL_DOCTEST_DOC_NOT_FOUND", dc.failureToken(error.DoctestDocNotFound));
    try expectEqualStrings("ZNTL_AI_REPORT_NOT_FOUND", dc.failureToken(error.AiReportNotFound));
    try expectEqualStrings("ZNTL_AI_DISABLED", dc.failureToken(error.AiDisabled));
}

// --- Case-ref resolution ---------------------------------------------------

test "resolveCase resolves a durable dt id and a source ref, rejects unknown" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const report = parseValue(arena, report_snapshot);

    const by_id = dc.resolveCase(report, "dt_01hr7p6h0v2fj3drdzt9k2a0xe") orelse return error.TestUnexpectedResult;
    try expectEqualStrings("docs/CLI_SPEC.md", by_id.object.get("file").?.string);

    const by_ref = dc.resolveCase(report, "docs/CLI_SPEC.md:47:help-output") orelse return error.TestUnexpectedResult;
    try expectEqualStrings("dt_01hr7p6h0v2fj3drdzt9k2a0xe", by_ref.object.get("id").?.string);

    // Anchor-line source ref also resolves (line 47 is the case anchor).
    const by_line = dc.resolveCase(report, "docs/CLI_SPEC.md:47") orelse return error.TestUnexpectedResult;
    try expectEqualStrings("dt_01hr7p6h0v2fj3drdzt9k2a0xe", by_line.object.get("id").?.string);

    try expect(dc.resolveCase(report, "dt_does_not_exist") == null);
    try expect(dc.resolveCase(report, "docs/CLI_SPEC.md:999") == null);
}

// --- Doctest context validation --------------------------------------------

test "buildPrompt embeds a valid doctest context and names the flow response schema" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const report = parseValue(arena, report_snapshot);
    const case = dc.resolveCase(report, "dt_01hr7p6h0v2fj3drdzt9k2a0xe").?;

    const ctx = try dc.buildContextValue(arena, .explain_doctest_failure, .stub, .{ .case = case }, stubSettings());
    try expectEqual(dc.ContextViolation.ok, dc.validateContext(ctx));
    try expectEqualStrings("zentinel.ai.doctest.context.v1", ctx.object.get("schema_version").?.string);
    try expectEqualStrings("case_failure", ctx.object.get("evidence").?.object.get("kind").?.string);

    const prompt = try dc.buildPromptValue(arena, .explain_doctest_failure, ctx);
    try expectEqual(dc.PromptViolation.ok, dc.validatePrompt(prompt));
    try expectEqualStrings("zentinel.ai.explain.response.v1", prompt.object.get("response_schema").?.object.get("name").?.string);
    try expectEqualStrings("explain_doctest_failure", prompt.object.get("flow").?.string);
}

test "validateContext rejects the deferred survivor flow and survivor evidence (task 067)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const survivor_flow = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.doctest.context.v1", "flow": "explain_doctest_survivor",
        \\  "created_by": "zentinel", "provider_mode": "stub",
        \\  "project": {"name":"x","root_label":"<project>","zig_version":"0.16.0","zentinel_version":"0.0.0"},
        \\  "doctest": {"id":"dt_x","file":"docs/x.md","line_start":1,"line_end":2,"source_ref":"docs/x.md:1","block_refs":[],"kind":"mutation","status":"survived"},
        \\  "evidence": {"kind":"doctest_survivor"},
        \\  "privacy": {"remote_allowed":false,"source_context_policy":"none","redactions_applied":[]} }
    );
    try expectEqual(dc.ContextViolation.survivor_flow, dc.validateContext(survivor_flow));
}

test "validatePrompt rejects the survivor flow and a mutation (non-doctest) context" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const survivor = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.prompt.v1", "flow": "explain_doctest_survivor",
        \\  "instructions": ["Use only provided context."],
        \\  "context": { "schema_version": "zentinel.ai.doctest.context.v1" },
        \\  "response_schema": { "name": "zentinel.ai.explain.response.v1" } }
    );
    try expectEqual(dc.PromptViolation.survivor_flow, dc.validatePrompt(survivor));

    const wrong_ctx = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.prompt.v1", "flow": "suggest_doctest",
        \\  "instructions": ["Use only provided context."],
        \\  "context": { "schema_version": "zentinel.ai.context.v1" },
        \\  "response_schema": { "name": "zentinel.ai.doctest.suggest.response.v1" } }
    );
    try expectEqual(dc.PromptViolation.unknown_context_schema, dc.validatePrompt(wrong_ctx));
}

// --- Response validation ---------------------------------------------------

test "validateSuggestResponse rejects >3 suggestions and absolute paths" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const ok = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.doctest.suggest.response.v1",
        \\  "suggestions": [ {"target_file":"docs/CONFIG_SPEC.md","line_hint":19,"reason":"r","block":"```toml config\nx\n```"} ] }
    );
    try expectEqual(dc.ResponseViolation.ok, dc.validateSuggestResponse(ok));

    const absolute = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.doctest.suggest.response.v1",
        \\  "suggestions": [ {"target_file":"/etc/passwd","line_hint":null,"reason":"r","block":"x"} ] }
    );
    try expectEqual(dc.ResponseViolation.bad_path, dc.validateSuggestResponse(absolute));

    const too_many = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.doctest.suggest.response.v1",
        \\  "suggestions": [
        \\    {"target_file":"docs/a.md","line_hint":null,"reason":"r","block":"x"},
        \\    {"target_file":"docs/b.md","line_hint":null,"reason":"r","block":"x"},
        \\    {"target_file":"docs/c.md","line_hint":null,"reason":"r","block":"x"},
        \\    {"target_file":"docs/d.md","line_hint":null,"reason":"r","block":"x"} ] }
    );
    try expectEqual(dc.ResponseViolation.too_many_suggestions, dc.validateSuggestResponse(too_many));
}

test "validateSnapshotReviewResponse accepts valid review and rejects bad classification" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const ok = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.doctest.snapshot_review.response.v1", "classification": "wording_change",
        \\  "summary": "heading wording changed", "risk": "medium",
        \\  "evidence_refs": [ {"kind":"block_ref","ref":"docs/CLI_SPEC.md:54:help-output"} ],
        \\  "next_action": "review wording before updating expected output" }
    );
    try expectEqual(dc.ResponseViolation.ok, dc.validateSnapshotReviewResponse(ok));

    const bad = parseValue(arena,
        \\{ "schema_version": "zentinel.ai.doctest.snapshot_review.response.v1", "classification": "approve_update",
        \\  "summary": "x", "risk": "low", "evidence_refs": [], "next_action": "y" }
    );
    try expectEqual(dc.ResponseViolation.bad_enum, dc.validateSnapshotReviewResponse(bad));
}

// --- Stub command runs + snapshots -----------------------------------------

test "run explain_doctest_failure produces a valid, snapshotted explain response" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.run(arena, .{
        .flow = .explain_doctest_failure,
        .case_ref = "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
        .doc_path = null,
        .doc_exists = false,
        .provider_override = .stub,
        .report_json = report_snapshot,
        .settings = stubSettings(),
    }, .json);
    try expectEqual(@as(u8, 0), out.exit_code);
    const value = parseValue(arena, out.body);
    try expectEqual(command.ResponseViolation.ok, command.validateResponse(.explain, value));
    try expectEqualStrings("doctest_output_mismatch", value.object.get("classification").?.string);
    try expectEqualStrings(explain_snapshot, out.body);
}

test "run review_snapshot produces a valid, snapshotted snapshot-review response" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.run(arena, .{
        .flow = .review_snapshot,
        .case_ref = "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
        .doc_path = null,
        .doc_exists = false,
        .provider_override = .stub,
        .report_json = report_snapshot,
        .settings = stubSettings(),
    }, .json);
    try expectEqual(@as(u8, 0), out.exit_code);
    const value = parseValue(arena, out.body);
    try expectEqual(dc.ResponseViolation.ok, dc.validateSnapshotReviewResponse(value));
    try expectEqualStrings(review_snapshot_fixture, out.body);
}

test "run suggest_doctest requires an existing doc and snapshots its suggestion" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.run(arena, .{
        .flow = .suggest_doctest,
        .case_ref = null,
        .doc_path = "docs/CONFIG_SPEC.md",
        .doc_exists = true,
        .provider_override = .stub,
        .report_json = null,
        .settings = stubSettings(),
    }, .json);
    try expectEqual(@as(u8, 0), out.exit_code);
    const value = parseValue(arena, out.body);
    try expectEqual(dc.ResponseViolation.ok, dc.validateSuggestResponse(value));
    try expectEqualStrings(suggest_snapshot, out.body);

    // A missing docs path is a usage error, not a provider error.
    try expectError(error.DoctestDocNotFound, dc.run(arena, .{
        .flow = .suggest_doctest,
        .case_ref = null,
        .doc_path = "docs/CONFIG_SPEC.md",
        .doc_exists = false,
        .provider_override = .stub,
        .report_json = null,
        .settings = stubSettings(),
    }, .json));
}

test "run suggest_missing_doctests snapshots a bounded suggestion" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.run(arena, .{
        .flow = .suggest_missing_doctests,
        .case_ref = null,
        .doc_path = "docs/CONFIG_SPEC.md",
        .doc_exists = true,
        .provider_override = .stub,
        .report_json = null,
        .settings = stubSettings(),
    }, .json);
    try expectEqual(@as(u8, 0), out.exit_code);
    const value = parseValue(arena, out.body);
    try expectEqual(dc.ResponseViolation.ok, dc.validateSuggestResponse(value));
    try expectEqualStrings(missing_snapshot, out.body);
}

// --- Error paths -----------------------------------------------------------

test "run explain with a missing report is a ZNTL_AI_REPORT_NOT_FOUND usage error" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try expectError(error.AiReportNotFound, dc.run(arena, .{
        .flow = .explain_doctest_failure,
        .case_ref = "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
        .doc_path = null,
        .doc_exists = false,
        .provider_override = .stub,
        .report_json = null,
        .settings = stubSettings(),
    }, .json));
}

test "run explain with an unknown case ref is ZNTL_DOCTEST_CASE_NOT_FOUND" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try expectError(error.DoctestCaseNotFound, dc.run(arena, .{
        .flow = .explain_doctest_failure,
        .case_ref = "dt_unknown",
        .doc_path = null,
        .doc_exists = false,
        .provider_override = .stub,
        .report_json = report_snapshot,
        .settings = stubSettings(),
    }, .json));
}

test "run with AI disabled fails before touching the report or docs" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var settings = stubSettings();
    settings.ai_enabled = false;
    settings.config_mode = .disabled;
    try expectError(error.AiDisabled, dc.run(arena, .{
        .flow = .explain_doctest_failure,
        .case_ref = "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
        .doc_path = null,
        .doc_exists = false,
        .provider_override = null,
        .report_json = report_snapshot,
        .settings = settings,
    }, .json));
}
