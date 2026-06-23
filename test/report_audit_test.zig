// Report-cluster audit fixes (C6, C12, C13). Self-contained builders (so this
// file never collides with report_renderers_test.zig) exercise:
//   - C13: internal_error rendering in the text and JUnit renderers;
//   - C12: second-oracle validate() arms for run.error blankness and
//          baseline/preflight command phase;
//   - C6:  the status-neutral "selected tests:" verbose label.
const std = @import("std");
const zentinel = @import("zentinel");

const report = zentinel.report;
const report_text = zentinel.report_text;
const report_junit = zentinel.report_junit;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

// --- Builders ---------------------------------------------------------------

fn run(status: report.RunStatus, err: ?report.RunError) report.Run {
    return .{
        .id = "run_audit0000000000",
        .status = status,
        .@"error" = err,
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .command = "zentinel run",
        .config_hash = "sha256:0000",
        .project_root = "<project>",
        .started_at = "1970-01-01T00:00:00Z",
        .duration_ms = 0,
    };
}

fn baselineCommand(phase: report.Phase, status: report.CommandStatus) report.CommandResult {
    return .{
        .command = .{ .original = "zig build test", .argv = &.{ "zig", "build", "test" }, .cwd = "<project>", .environment_policy = .minimal, .shell = false },
        .phase = phase,
        .status = status,
        .exit_code = if (status == .passed) 0 else 1,
        .timed_out = false,
        .failure_kind = if (status == .passed) .none else .test_failure,
        .duration_ms = 0,
        .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "", .failure_summary = "" },
        .skip_reason = null,
    };
}

fn preflightCommand(phase: report.Phase) report.CommandResult {
    return .{
        .command = .{ .original = "zig test src/x.zig", .argv = &.{ "zig", "test", "src/x.zig" }, .cwd = "<project>", .environment_policy = .minimal, .shell = false },
        .phase = phase,
        .status = .passed,
        .exit_code = 0,
        .timed_out = false,
        .failure_kind = .none,
        .duration_ms = 0,
        .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "", .failure_summary = "" },
        .skip_reason = null,
    };
}

const baseline_pass_cmds = [_]report.CommandResult{baselineCommand(.baseline, .passed)};
// A baseline command mistakenly stamped with the mutant phase (C12 negative case).
const baseline_wrongphase_cmds = [_]report.CommandResult{baselineCommand(.mutant, .passed)};
// A preflight command mistakenly stamped with the mutant phase (C12 negative case).
const preflight_wrongphase_cmds = [_]report.CommandResult{preflightCommand(.mutant)};
const preflight_ok_cmds = [_]report.CommandResult{preflightCommand(.selection_preflight)};

fn mutant(display_id: u32, status: report.ResultStatus, preflights: []const report.CommandResult) report.Mutant {
    return .{
        .id = "m_0000000000000000000000000a",
        .display_id = display_id,
        .backend = .ast,
        .backend_stability = .stable,
        .operator = "comparison_boundary",
        .operator_stability = .stable,
        .file = "src/range.zig",
        .span = .{ .byte_start = 10, .byte_end = 12, .line_start = 12, .column_start = 9, .line_end = 12, .column_end = 11 },
        .original = ">=",
        .replacement = ">",
        .diff = &.{ "- if (idx >= items.len) return error.OutOfBounds;", "+ if (idx > items.len) return error.OutOfBounds;" },
        .expected_compile = .compiles,
        .result = .{
            .status = status,
            .mode = .Debug,
            .commands = &.{},
            .phase = .mutant,
            .duration_ms = 0,
            .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "", .failure_summary = "" },
            .skip_reason = null,
        },
        .test_selection = .{ .strategy = .same_file, .selected = &.{}, .commands = &.{"zig test src/range.zig"}, .preflight_commands = preflights, .fallback_used = false },
        .advisory = .{ .equivalent_risks = &.{}, .ai = null },
    };
}

fn completedReport(mutants: []const report.Mutant) report.Report {
    return .{
        .run = run(.completed, null),
        .baseline = .{ .status = .passed, .commands = &baseline_pass_cmds },
        .summary = report.summarize(mutants),
        .mutants = mutants,
    };
}

/// A minimal, otherwise-valid internal_error report: baseline not_run, no
/// mutants, all-zero summary, and a populated run.error (validate requires it).
fn internalErrorReport(err: ?report.RunError) report.Report {
    return .{
        .run = run(.internal_error, err),
        .baseline = .{ .status = .not_run, .commands = &.{} },
        .summary = .{},
        .mutants = &.{},
    };
}

const sample_error = report.RunError{
    .code = "ZNTL_INTERNAL_INVARIANT",
    .message = "worker pool arena invariant violated",
    .phase = .internal,
    .details = &.{},
};

// --- C13: internal_error rendering ------------------------------------------

test "C13 text renderer surfaces internal_error code and message, no mutant listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const text = try report_text.render(a, internalErrorReport(sample_error), .verbose);
    try expect(contains(text, "internal error[ZNTL_INTERNAL_INVARIANT]:"));
    try expect(contains(text, "worker pool arena invariant violated"));
    // No mutants array, so no per-mutant status lines and no summary count line.
    try expect(!contains(text, "killed"));
    try expect(!contains(text, "mutants:"));
}

test "C13 junit renderer emits a single internal_error testcase with errors=1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const xml = try report_junit.render(a, internalErrorReport(sample_error), false);
    try expect(contains(xml, "tests=\"1\""));
    try expect(contains(xml, "errors=\"1\""));
    try expect(contains(xml, "failures=\"0\""));
    try expect(contains(xml, "name=\"internal_error\""));
    try expect(contains(xml, "<error type=\"zentinel.internal_error\""));
    try expect(contains(xml, "worker pool arena invariant violated"));
    // No mutant testcases are emitted for a run-level internal error.
    try expect(!contains(xml, "classname=\"zentinel.mutant\""));
}

test "C13 junit escapes an internal_error message carrying XML metacharacters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const err = report.RunError{
        .code = "ZNTL_INTERNAL_INVARIANT",
        .message = "bad <tag> & \"quote\"",
        .phase = .internal,
        .details = &.{},
    };
    const xml = try report_junit.render(a, internalErrorReport(err), false);
    // The raw metacharacters must not survive into the attribute value.
    try expect(contains(xml, "&lt;tag&gt;"));
    try expect(contains(xml, "&amp;"));
    try expect(contains(xml, "&quot;quote&quot;"));
    try expect(!contains(xml, "message=\"bad <tag>"));
}

// --- C12: second-oracle validate() arms -------------------------------------

test "C12 a populated internal_error report validates ok" {
    try expectEqual(report.Violation.ok, report.validate(internalErrorReport(sample_error)));
}

test "C12 internal_error with a blank run.error code is rejected" {
    const err = report.RunError{ .code = "", .message = "nonempty", .phase = .internal, .details = &.{} };
    try expectEqual(report.Violation.run_error_code_blank, report.validate(internalErrorReport(err)));
}

test "C12 internal_error with a blank run.error message is rejected" {
    const err = report.RunError{ .code = "ZNTL_INTERNAL_INVARIANT", .message = "", .phase = .internal, .details = &.{} };
    try expectEqual(report.Violation.run_error_message_blank, report.validate(internalErrorReport(err)));
}

test "C12 internal_error with a null run.error is still rejected" {
    try expectEqual(report.Violation.internal_error_requires_run_error, report.validate(internalErrorReport(null)));
}

test "C12 a baseline command stamped with the wrong phase is rejected" {
    var rep = completedReport(&.{});
    rep.baseline = .{ .status = .passed, .commands = &baseline_wrongphase_cmds };
    try expectEqual(report.Violation.baseline_command_phase, report.validate(rep));
}

test "C12 a preflight command stamped with the wrong phase is rejected" {
    const m = [_]report.Mutant{mutant(1, .killed, &preflight_wrongphase_cmds)};
    try expectEqual(report.Violation.preflight_command_phase, report.validate(completedReport(&m)));
}

test "C12 a preflight command with the correct selection_preflight phase validates ok" {
    const m = [_]report.Mutant{mutant(1, .killed, &preflight_ok_cmds)};
    try expectEqual(report.Violation.ok, report.validate(completedReport(&m)));
}

// --- C6: status-neutral verbose label ---------------------------------------

test "C6 verbose label does not claim selected tests passed for a killed mutant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A killed mutant shown in verbose mode: the label must be status-neutral.
    const m = [_]report.Mutant{mutant(1, .killed, &.{})};
    const text = try report_text.render(a, completedReport(&m), .verbose);
    try expect(contains(text, "killed 1 comparison_boundary"));
    try expect(contains(text, "  selected tests: zig test src/range.zig"));
    try expect(!contains(text, "selected tests passed"));
}
