const std = @import("std");
const zentinel = @import("zentinel");
const dc = zentinel.ai.doctest_command;
const command = zentinel.ai.command;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const survivor_report = @embedFile("fixtures/ai/doctest_survivor/report.json");
const survivor_ref = "ds_2xxh4aj0c4vxrpnzr204z062ep";

fn parseValue(arena: std.mem.Allocator, src: []const u8) std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, arena, src, .{}) catch unreachable;
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

fn baseInput() dc.SurvivorInput {
    return .{
        .survivor_ref = survivor_ref,
        .provider_override = .stub,
        .report_json = survivor_report,
        .settings = settings(),
    };
}

fn readFile(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

// 1. explicit mutation-aware report + the default doctest report path.
test "explain-survivor with an explicit mutation-aware report explains the survivor" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.runSurvivor(arena, baseInput(), .json);
    try expectEqual(@as(u8, 0), out.exit_code);
    const value = parseValue(arena, out.body);
    try expectEqualStrings("zentinel.ai.explain.response.v1", value.object.get("schema_version").?.string);
    try expectEqualStrings("doctest_survivor_missing_assertion", value.object.get("classification").?.string);
}

test "explain-survivor consumes the default doctest report path" {
    // The CLI adapter loads dc.default_report_path when --input-report is omitted.
    try expect(std.mem.endsWith(u8, dc.default_report_path, "doctest/report.json"));
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.runSurvivor(arena, baseInput(), .json);
    try expectEqual(@as(u8, 0), out.exit_code);
}

// 2. missing report -> ZNTL_AI_REPORT_NOT_FOUND.
test "explain-survivor with a missing report is ZNTL_AI_REPORT_NOT_FOUND" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var input = baseInput();
    input.report_json = null;
    try expectError(error.AiReportNotFound, dc.runSurvivor(arena, input, .json));
    try expectEqualStrings("ZNTL_AI_REPORT_NOT_FOUND", dc.failureToken(error.AiReportNotFound));
}

// 3. unresolved survivor ref -> ZNTL_DOCTEST_SURVIVOR_NOT_FOUND.
test "explain-survivor with an unresolved survivor ref is ZNTL_DOCTEST_SURVIVOR_NOT_FOUND" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var input = baseInput();
    input.survivor_ref = "ds_doesnotexist00000000000000";
    try expectError(error.DoctestSurvivorNotFound, dc.runSurvivor(arena, input, .json));
    try expectEqualStrings("ZNTL_DOCTEST_SURVIVOR_NOT_FOUND", dc.failureToken(error.DoctestSurvivorNotFound));
}

// 4. schema extension without weakening the 055 variants.
test "ai.doctest.context.v1 schema adds the survivor flow and evidence without weakening task 055" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const schema = try readFile(arena, "schemas/ai.doctest.context.v1.schema.json");
    try expect(contains(schema, "explain_doctest_survivor"));
    try expect(contains(schema, "doctest_survivor"));
    // The task-055 non-survivor flows and evidence variants are still present.
    inline for (.{
        "explain_doctest_failure", "suggest_doctest", "review_snapshot", "suggest_missing_doctests",
        "case_failure",            "docs_target",     "snapshot_diff",   "missing_doctests",
    }) |needle| try expect(contains(schema, needle));
}

// 5. context fixture: the survivor context records all required evidence.
test "survivor context records flow, mutation doctest, and survivor evidence" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const report = parseValue(arena, survivor_report);
    const case = dc.resolveSurvivor(report, survivor_ref).?;
    const ctx = try dc.buildSurvivorContextValue(arena, .stub, case, settings());
    try expectEqual(dc.ContextViolation.ok, dc.validateSurvivorContext(ctx));

    const o = ctx.object;
    try expectEqualStrings("zentinel.ai.doctest.context.v1", o.get("schema_version").?.string);
    try expectEqualStrings("explain_doctest_survivor", o.get("flow").?.string);
    try expectEqualStrings("mutation", o.get("doctest").?.object.get("kind").?.string);
    try expectEqualStrings("survived", o.get("doctest").?.object.get("status").?.string);

    const ev = o.get("evidence").?.object;
    try expectEqualStrings("doctest_survivor", ev.get("kind").?.string);
    try expect(std.mem.startsWith(u8, ev.get("survivor_ref").?.string, "ds_"));
    try expect(std.mem.startsWith(u8, ev.get("source_case").?.object.get("doctest_case_id").?.string, "dt_"));

    const mc = ev.get("mutation_case").?.object;
    try expect(std.mem.startsWith(u8, mc.get("case_id").?.string, "dm_"));
    try expect(std.mem.startsWith(u8, mc.get("mutant_id").?.string, "m_"));
    try expectEqualStrings("comparison_boundary", mc.get("operator").?.string);
    try expect(mc.get("mutated_diff").?.array.items.len > 0);
    try expectEqualStrings("stable", mc.get("backend_stability").?.string);
    try expectEqualStrings("none", mc.get("runner_evidence").?.object.get("failure_kind").?.string);
}

// 6. resolution rejects non-survived and unknown refs.
test "survivor resolution matches only non-null survived survivor refs" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const report = parseValue(arena, survivor_report);
    try expect(dc.resolveSurvivor(report, survivor_ref) != null);
    try expect(dc.resolveSurvivor(report, "ds_unknown0000000000000000000") == null);
    // killed and skipped documentation mutants carry a null survivor_ref and never resolve,
    // even by their dm_/m_ ids.
    try expect(dc.resolveSurvivor(report, "dm_killed00000000000000000000") == null);
    try expect(dc.resolveSurvivor(report, "m_killed0000000000000000000000") == null);
    try expect(dc.resolveSurvivor(report, "dm_skipped0000000000000000000") == null);
}

// 7. stub output snapshot uses the doctest survivor classification label.
test "survivor stub output uses the doctest survivor classification label" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.runSurvivor(arena, baseInput(), .text);
    try expectEqual(@as(u8, 0), out.exit_code);
    try expect(contains(out.body, "classification: doctest_survivor_missing_assertion"));
    try expect(contains(out.body, "next action:"));
}

// 8. advisory only: no change to survivor status, the report, or expected blocks.
test "explain-survivor does not change survivor status, report files, or expected output" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const out = try dc.runSurvivor(arena, baseInput(), .json);
    const value = parseValue(arena, out.body);
    // The advisory response carries no status, apply, or kill verdict.
    try expect(value.object.get("status") == null);
    try expect(value.object.get("apply_update") == null);
    try expect(value.object.get("kill") == null);
    // The input report (an immutable slice) still classifies the survivor as survived.
    const after = parseValue(arena, survivor_report);
    try expectEqualStrings("survived", dc.resolveSurvivor(after, survivor_ref).?.object.get("status").?.string);
}
