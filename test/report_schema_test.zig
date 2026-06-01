const std = @import("std");
const zentinel = @import("zentinel");
const report = zentinel.report;
const harness = @import("support/harness.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const minimal_snapshot = @embedFile("snapshots/report_minimal.json");

fn readJson(a: std.mem.Allocator, path: []const u8) !std.json.Value {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
    return std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{});
}

fn arrayContainsString(items: []const std.json.Value, needle: []const u8) bool {
    for (items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, needle)) return true;
    }
    return false;
}

// --- Reusable, statically-scoped report components -------------------------

const empty_evidence = report.Evidence{};

const passed_baseline_cmd = report.CommandResult{
    .command = .{ .original = "zig build test", .argv = &.{ "zig", "build", "test" }, .cwd = "<project>" },
    .phase = .baseline,
    .status = .passed,
    .exit_code = 0,
    .timed_out = false,
    .failure_kind = .none,
    .duration_ms = 0,
    .evidence = empty_evidence,
    .skip_reason = null,
};
const baseline_commands = [_]report.CommandResult{passed_baseline_cmd};

const failed_baseline_cmd = report.CommandResult{
    .command = .{ .original = "zig build test", .argv = &.{ "zig", "build", "test" }, .cwd = "<project>" },
    .phase = .baseline,
    .status = .failed,
    .exit_code = 1,
    .timed_out = false,
    .failure_kind = .test_failure,
    .duration_ms = 0,
    .evidence = .{ .failure_summary = "tests failed" },
    .skip_reason = null,
};
const failed_baseline_commands = [_]report.CommandResult{failed_baseline_cmd};

const timeout_baseline_cmd = report.CommandResult{
    .command = .{ .original = "zig build test", .argv = &.{ "zig", "build", "test" }, .cwd = "<project>" },
    .phase = .baseline,
    .status = .timeout,
    .exit_code = null,
    .timed_out = true,
    .failure_kind = .timeout,
    .duration_ms = 0,
    .evidence = empty_evidence,
    .skip_reason = null,
};
const timeout_baseline_commands = [_]report.CommandResult{timeout_baseline_cmd};

const no_commands = [_]report.CommandResult{};

const passed_mutant_cmd = report.CommandResult{
    .command = .{ .original = "zig test src/range.zig", .argv = &.{ "zig", "test", "src/range.zig" }, .cwd = "<project>" },
    .phase = .mutant,
    .status = .passed,
    .exit_code = 0,
    .timed_out = false,
    .failure_kind = .none,
    .duration_ms = 0,
    .evidence = empty_evidence,
    .skip_reason = null,
};
const mutant_commands = [_]report.CommandResult{passed_mutant_cmd};

const no_selected = [_]report.SelectedTest{};
const selection_commands = [_][]const u8{"zig test src/range.zig"};
const no_diff = [_][]const u8{};
const no_risks = [_][]const u8{};

const sample_span = report.Span{ .byte_start = 310, .byte_end = 312, .line_start = 12, .column_start = 13, .line_end = 12, .column_end = 15 };

const sample_selection = report.TestSelection{
    .strategy = .same_file,
    .selected = &no_selected,
    .commands = &selection_commands,
    .preflight_commands = &no_commands,
    .fallback_used = false,
};

const survived_result = report.Result{
    .status = .survived,
    .mode = .Debug,
    .commands = &mutant_commands,
    .phase = .mutant,
    .duration_ms = 0,
    .evidence = empty_evidence,
    .skip_reason = null,
};

const sample_mutant = report.Mutant{
    .id = "m_01hr7p6h0v2fj3drdzt9k2a0xe",
    .display_id = 1,
    .backend = .ast,
    .backend_stability = .stable,
    .operator = "comparison_boundary",
    .operator_stability = .stable,
    .file = "src/range.zig",
    .span = sample_span,
    .original = ">=",
    .replacement = ">",
    .diff = &no_diff,
    .expected_compile = .compiles,
    .result = survived_result,
    .test_selection = sample_selection,
    .advisory = .{ .equivalent_risks = &no_risks, .ai = null },
};
const one_mutant = [_]report.Mutant{sample_mutant};
const no_mutants = [_]report.Mutant{};

fn baseRun(status: report.RunStatus, err: ?report.RunError) report.Run {
    return .{
        .id = "run_0000000000000000000000000",
        .status = status,
        .@"error" = err,
        .zentinel_version = "0.1.0",
        .zig_version = "0.16.0",
        .command = "zentinel run",
        .config_hash = "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        .project_root = "<project>",
        .started_at = "<normalized>",
        .duration_ms = 0,
    };
}

fn completedReport(mutants: []const report.Mutant) report.Report {
    return .{
        .run = baseRun(.completed, null),
        .baseline = .{ .status = .passed, .commands = &baseline_commands },
        .summary = report.summarize(mutants),
        .mutants = mutants,
    };
}

// --- Serialization ---------------------------------------------------------

test "minimal report serializes to the deterministic snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const json = try report.toJson(arena.allocator(), completedReport(&no_mutants));
    try harness.expectSnapshot(minimal_snapshot, json);
}

test "doctest report schema matches command and run_error contracts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const schema = try readJson(arena.allocator(), "schemas/doctest.report.v1.schema.json");
    const defs = schema.object.get("$defs").?.object;

    const run_error = defs.get("run_error").?.object;
    const required = run_error.get("required").?.array.items;
    try expect(!arrayContainsString(required, "details"));

    const command_def = defs.get("command").?.object;
    const props = command_def.get("properties").?.object;
    const argv = props.get("argv").?.object;
    const min_items = argv.get("minItems") orelse return error.TestUnexpectedResult;
    try expectEqual(@as(i64, 1), min_items.integer);

    const shell = props.get("shell").?.object;
    const shell_const = shell.get("const") orelse return error.TestUnexpectedResult;
    try expect(shell_const.bool == false);

    const evidence_props = defs.get("mutation_runner_evidence").?.object.get("properties").?.object;
    const failure_kind_enum = evidence_props.get("failure_kind").?.object.get("enum").?.array.items;
    try expect(arrayContainsString(failure_kind_enum, "invalid"));
}

test "mutant entries sort by canonical candidate order with sequential display ids" {
    var m1 = sample_mutant;
    m1.file = "b.zig";
    m1.display_id = 99;
    var m2 = sample_mutant;
    m2.file = "a.zig";
    m2.id = "m_aaaaaaaaaaaaaaaaaaaaaaaaaa";
    m2.display_id = 99;
    var arr = [_]report.Mutant{ m1, m2 };
    report.sortAndAssignDisplayIds(&arr);
    try expectEqualStrings("a.zig", arr[0].file);
    try expectEqual(@as(u32, 1), arr[0].display_id);
    try expectEqualStrings("b.zig", arr[1].file);
    try expectEqual(@as(u32, 2), arr[1].display_id);
}

// --- Summary derivation ----------------------------------------------------

test "summary counts derive only from mutant entries" {
    const s = report.summarize(&one_mutant);
    try expectEqual(@as(u64, 1), s.total);
    try expectEqual(@as(u64, 1), s.survived);
    try expectEqual(@as(u64, 0), s.killed);
}

test "validate accepts a well-formed completed report" {
    try expectEqual(report.Violation.ok, report.validate(completedReport(&one_mutant)));
}

test "validate rejects a summary total that does not match mutants" {
    var r = completedReport(&one_mutant);
    r.summary.total = 5;
    try expectEqual(report.Violation.summary_total_mismatch, report.validate(r));
}

test "validate rejects per-status counts that do not match mutants" {
    var r = completedReport(&one_mutant);
    r.summary.killed = 1;
    r.summary.survived = 0;
    try expectEqual(report.Violation.summary_count_mismatch, report.validate(r));
}

// --- Run-level status invariants -------------------------------------------

test "completed report requires a passed baseline" {
    var r = completedReport(&no_mutants);
    r.baseline.status = .failed;
    r.baseline.commands = &failed_baseline_commands;
    try expectEqual(report.Violation.completed_requires_baseline_passed, report.validate(r));
}

test "baseline_failed requires failed baseline, empty mutants, and zero counts" {
    const ok = report.Report{
        .run = baseRun(.baseline_failed, null),
        .baseline = .{ .status = .failed, .commands = &failed_baseline_commands },
        .summary = .{},
        .mutants = &no_mutants,
    };
    try expectEqual(report.Violation.ok, report.validate(ok));

    var bad_status = ok;
    bad_status.baseline = .{ .status = .passed, .commands = &baseline_commands };
    try expectEqual(report.Violation.baseline_failed_requires_failed_baseline, report.validate(bad_status));

    var bad_mutants = ok;
    bad_mutants.mutants = &one_mutant;
    bad_mutants.summary = report.summarize(&one_mutant);
    try expectEqual(report.Violation.baseline_failed_requires_empty_mutants, report.validate(bad_mutants));
}

test "baseline timeout must be represented as a baseline failure" {
    const ok = report.Report{
        .run = baseRun(.baseline_failed, null),
        .baseline = .{ .status = .failed, .commands = &timeout_baseline_commands },
        .summary = .{},
        .mutants = &no_mutants,
    };
    try expectEqual(report.Violation.ok, report.validate(ok));

    // A baseline timeout under a non-baseline_failed run is rejected.
    var bad = ok;
    bad.run = baseRun(.completed, null);
    bad.baseline = .{ .status = .passed, .commands = &timeout_baseline_commands };
    try expectEqual(report.Violation.baseline_timeout_requires_baseline_failed, report.validate(bad));
}

test "internal_error requires a run.error object and others require null" {
    const err = report.RunError{ .code = "ZNTL_INTERNAL_INVARIANT", .message = "internal invariant violated", .phase = .internal };
    const ok = report.Report{
        .run = baseRun(.internal_error, err),
        .baseline = .{ .status = .not_run, .commands = &no_commands },
        .summary = .{},
        .mutants = &no_mutants,
    };
    try expectEqual(report.Violation.ok, report.validate(ok));

    var missing = ok;
    missing.run = baseRun(.internal_error, null);
    try expectEqual(report.Violation.internal_error_requires_run_error, report.validate(missing));

    var spurious = completedReport(&no_mutants);
    spurious.run = baseRun(.completed, err);
    try expectEqual(report.Violation.run_error_must_be_null, report.validate(spurious));
}

test "validate rejects baseline.status not_run with non-empty mutants" {
    const err = report.RunError{ .code = "ZNTL_INTERNAL_INVARIANT", .message = "boom", .phase = .internal };
    const r = report.Report{
        .run = baseRun(.internal_error, err),
        .baseline = .{ .status = .not_run, .commands = &no_commands },
        .summary = report.summarize(&one_mutant),
        .mutants = &one_mutant,
    };
    try expectEqual(report.Violation.baseline_not_run_with_mutants, report.validate(r));
}

// --- Command evidence + result invariants ----------------------------------

test "command evidence requires a non-empty argv[0]" {
    const empty_argv = [_][]const u8{};
    var bad_cmd = passed_baseline_cmd;
    bad_cmd.command.argv = &empty_argv;
    const bad_commands = [_]report.CommandResult{bad_cmd};
    var r = completedReport(&no_mutants);
    r.baseline = .{ .status = .passed, .commands = &bad_commands };
    try expectEqual(report.Violation.empty_argv0, report.validate(r));
}

test "skipped result requires a skip reason and other statuses require null" {
    var skipped = sample_mutant;
    skipped.result = survived_result;
    skipped.result.status = .skipped;
    skipped.result.commands = &no_commands;
    skipped.result.skip_reason = null;
    const skipped_arr = [_]report.Mutant{skipped};
    try expectEqual(report.Violation.skip_reason_required, report.validate(completedReport(&skipped_arr)));

    var spurious = sample_mutant;
    spurious.result.skip_reason = "should be null";
    const spurious_arr = [_]report.Mutant{spurious};
    try expectEqual(report.Violation.skip_reason_must_be_null, report.validate(completedReport(&spurious_arr)));
}

test "invalid result requires a patch/sandbox/backend failure summary prefix" {
    var ok = sample_mutant;
    ok.result.status = .invalid;
    ok.result.commands = &no_commands;
    ok.result.evidence = .{ .failure_summary = "patch: source span did not match" };
    const ok_arr = [_]report.Mutant{ok};
    try expectEqual(report.Violation.ok, report.validate(completedReport(&ok_arr)));

    var bad = ok;
    bad.result.evidence = .{ .failure_summary = "something went wrong" };
    const bad_arr = [_]report.Mutant{bad};
    try expectEqual(report.Violation.invalid_failure_summary_prefix, report.validate(completedReport(&bad_arr)));
}

test "validate rejects non-canonical display_id ordering" {
    var m1 = sample_mutant;
    m1.file = "a.zig";
    m1.display_id = 2;
    var m2 = sample_mutant;
    m2.file = "b.zig";
    m2.id = "m_bbbbbbbbbbbbbbbbbbbbbbbbbb";
    m2.display_id = 1;
    const arr = [_]report.Mutant{ m1, m2 };
    try expectEqual(report.Violation.display_id_ordering, report.validate(completedReport(&arr)));
}

// --- Structural / shape guarantees -----------------------------------------

test "mutant result uses a commands array, not a legacy single-command shape" {
    try expect(@hasField(report.Result, "commands"));
    try expect(!@hasField(report.Result, "command"));
    try expect(!@hasField(report.Result, "exit_code"));
    try expect(!@hasField(report.Result, "timed_out"));
}

test "cache diagnostics live only under diagnostics.cache" {
    try expect(@hasField(report.Diagnostics, "cache"));
    try expect(!@hasField(report.Report, "cache"));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const json = try report.toJson(arena.allocator(), completedReport(&no_mutants));
    try expect(std.mem.indexOf(u8, json, "\"diagnostics\"") != null);
    try expect(std.mem.indexOf(u8, json, "\"cache\"") != null);
}

test "test_selection carries exactly the documented fields" {
    inline for ([_][]const u8{ "strategy", "selected", "commands", "preflight_commands", "fallback_used" }) |field| {
        try expect(@hasField(report.TestSelection, field));
    }
}

test "selection preflight schema can represent skipped command evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const schema = try readJson(arena.allocator(), "schemas/report.v1.schema.json");
    const defs = schema.object.get("$defs").?.object;
    const preflight = defs.get("selection_preflight_command_result").?.object;
    const props = preflight.get("properties").?.object;

    const status_enum = props.get("status").?.object.get("enum").?.array.items;
    const failure_kind_enum = props.get("failure_kind").?.object.get("enum").?.array.items;
    try expect(arrayContainsString(status_enum, "skipped"));
    try expect(arrayContainsString(failure_kind_enum, "skipped"));

    const skip_type = props.get("skip_reason").?.object.get("type").?.array.items;
    try expect(arrayContainsString(skip_type, "string"));
    try expect(arrayContainsString(skip_type, "null"));
}

test "preflight command skip reasons follow the command status" {
    var skipped_preflight = passed_mutant_cmd;
    skipped_preflight.phase = .selection_preflight;
    skipped_preflight.status = .skipped;
    skipped_preflight.failure_kind = .skipped;
    skipped_preflight.exit_code = null;
    skipped_preflight.skip_reason = null;
    const skipped_preflights = [_]report.CommandResult{skipped_preflight};
    var skipped_selection = sample_selection;
    skipped_selection.preflight_commands = &skipped_preflights;
    var skipped_mutant = sample_mutant;
    skipped_mutant.test_selection = skipped_selection;
    const skipped_arr = [_]report.Mutant{skipped_mutant};
    try expectEqual(report.Violation.skip_reason_required, report.validate(completedReport(&skipped_arr)));

    var spurious_preflight = passed_mutant_cmd;
    spurious_preflight.phase = .selection_preflight;
    spurious_preflight.skip_reason = "should be null";
    const spurious_preflights = [_]report.CommandResult{spurious_preflight};
    var spurious_selection = sample_selection;
    spurious_selection.preflight_commands = &spurious_preflights;
    var spurious_mutant = sample_mutant;
    spurious_mutant.test_selection = spurious_selection;
    const spurious_arr = [_]report.Mutant{spurious_mutant};
    try expectEqual(report.Violation.skip_reason_must_be_null, report.validate(completedReport(&spurious_arr)));
}

test "backend_stability and operator_stability are distinct fields with separate enums" {
    try expect(sample_mutant.backend_stability == .stable);
    try expect(sample_mutant.operator_stability == .stable);
    try expect(report.BackendStability != report.OperatorStability);
}

test "result classification has no AI-owned classifier field; advisory.ai is separate" {
    try expect(!@hasField(report.Result, "classifier"));
    try expect(!@hasField(report.Result, "ai"));
    try expect(@hasField(report.Advisory, "ai"));
    // Advisory content does not change deterministic classification or summary.
    var m = sample_mutant;
    m.advisory = .{ .equivalent_risks = &no_risks, .ai = report.Ai{} };
    const arr = [_]report.Mutant{m};
    try expectEqual(report.Violation.ok, report.validate(completedReport(&arr)));
    try expectEqual(@as(u64, 1), report.summarize(&arr).survived);
}

test "repeated-run comparison ignores only observation metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var r1 = completedReport(&one_mutant);
    r1.run.id = "run_first";
    r1.run.started_at = "2026-05-29T00:00:00Z";
    r1.run.duration_ms = 1234;

    var r2 = completedReport(&one_mutant);
    r2.run.id = "run_second";
    r2.run.started_at = "2026-05-29T11:11:11Z";
    r2.run.duration_ms = 9999;

    const n1 = try report.normalizeForComparison(a, try report.toJson(a, r1));
    const n2 = try report.normalizeForComparison(a, try report.toJson(a, r2));
    try expectEqualStrings(n1, n2);
}
