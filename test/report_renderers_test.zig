const std = @import("std");
const zentinel = @import("zentinel");

const report = zentinel.report;
const report_text = zentinel.report_text;
const report_jsonl = zentinel.report_jsonl;
const report_junit = zentinel.report_junit;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// --- Report builders (hand-built so every status can be exercised) ----------

fn run(status: report.RunStatus) report.Run {
    return .{
        .id = "run_fixture00000000",
        .status = status,
        .@"error" = null,
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .command = "zentinel run",
        .config_hash = "sha256:0000",
        .project_root = "<project>",
        .started_at = "1970-01-01T00:00:00Z",
        .duration_ms = 0,
    };
}

fn baselineCommand(status: report.CommandStatus) report.CommandResult {
    return .{
        .command = .{ .original = "zig build test", .argv = &.{ "zig", "build", "test" }, .cwd = "<project>", .environment_policy = .minimal, .shell = false },
        .phase = .baseline,
        .status = status,
        .exit_code = if (status == .passed) 0 else null,
        .timed_out = status == .timeout,
        .failure_kind = if (status == .passed) .none else .timeout,
        .duration_ms = 0,
        .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "", .failure_summary = "" },
        .skip_reason = null,
    };
}

fn mutantCommand() report.CommandResult {
    return .{
        .command = .{ .original = "zig test src/range.zig", .argv = &.{ "zig", "test", "src/range.zig" }, .cwd = "<project>", .environment_policy = .minimal, .shell = false },
        .phase = .mutant,
        .status = .failed,
        .exit_code = 1,
        .timed_out = false,
        .failure_kind = .test_failure,
        .duration_ms = 0,
        .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "boom", .failure_summary = "ZNTL_RUNNER_COMMAND_FAILED" },
        .skip_reason = null,
    };
}

fn mutant(display_id: u32, status: report.ResultStatus, file: []const u8, with_command: bool) report.Mutant {
    const skip_reason: ?[]const u8 = if (status == .skipped) "deterministically skipped" else null;
    const failure_summary: []const u8 = if (status == .invalid) "sandbox: patch out of range" else "";
    return .{
        .id = "m_0000000000000000000000000a",
        .display_id = display_id,
        .backend = .ast,
        .backend_stability = .stable,
        .operator = "comparison_boundary",
        .operator_stability = .stable,
        .file = file,
        .span = .{ .byte_start = 10, .byte_end = 12, .line_start = 12, .column_start = 9, .line_end = 12, .column_end = 11 },
        .original = ">=",
        .replacement = ">",
        .diff = &.{ "- if (idx >= items.len) return error.OutOfBounds;", "+ if (idx > items.len) return error.OutOfBounds;" },
        .expected_compile = .compiles,
        .result = .{
            .status = status,
            .mode = .Debug,
            .commands = if (with_command) &mutant_cmds else &.{},
            .phase = .mutant,
            .duration_ms = 0,
            .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "", .failure_summary = failure_summary },
            .skip_reason = skip_reason,
        },
        .test_selection = .{ .strategy = .all, .selected = &.{}, .commands = &.{"zig test src/range.zig"}, .preflight_commands = &.{}, .fallback_used = false },
        .advisory = .{ .equivalent_risks = &.{}, .ai = null },
    };
}

// Container-scope command arrays: comptime-evaluated consts with stable
// addresses (a `&.{ runtimeCall() }` literal would dangle after the builder).
const baseline_pass_cmds = [_]report.CommandResult{baselineCommand(.passed)};
const baseline_timeout_cmds = [_]report.CommandResult{baselineCommand(.timeout)};
const mutant_cmds = [_]report.CommandResult{mutantCommand()};

fn completedReport(mutants: []const report.Mutant) report.Report {
    return .{
        .run = run(.completed),
        .baseline = .{ .status = .passed, .commands = &baseline_pass_cmds },
        .summary = report.summarize(mutants),
        .mutants = mutants,
    };
}

fn baselineFailedReport() report.Report {
    return .{
        .run = run(.baseline_failed),
        .baseline = .{ .status = .failed, .commands = &baseline_timeout_cmds },
        .summary = .{},
        .mutants = &.{},
    };
}

fn checkSnapshot(a: std.mem.Allocator, path: []const u8, actual: []const u8) !void {
    const io = std.testing.io;
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, a, std.Io.Limit.limited(1 << 20)) catch |err| switch (err) {
        error.FileNotFound => return err,
        else => return err,
    };
    try expectEqualStrings(existing, actual);
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

// --- Snapshots --------------------------------------------------------------

test "snapshot: survivor-focused text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = [_]report.Mutant{ mutant(1, .killed, "src/calc.zig", true), mutant(2, .survived, "src/range.zig", false) };
    const text = try report_text.render(a, completedReport(&m), .normal);
    try checkSnapshot(a, "test/snapshots/report_survivors.txt", text);
}

test "snapshot: jsonl emits one object per line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = [_]report.Mutant{ mutant(1, .killed, "src/calc.zig", true), mutant(2, .survived, "src/range.zig", false) };
    const jsonl = try report_jsonl.render(a, completedReport(&m));
    // Header line + one line per mutant, each independently parseable.
    var lines: usize = 0;
    var it = std.mem.splitScalar(u8, std.mem.trim(u8, jsonl, "\n"), '\n');
    while (it.next()) |line| {
        lines += 1;
        var parsed = try std.json.parseFromSlice(std.json.Value, a, line, .{});
        parsed.deinit();
    }
    try expectEqual(@as(usize, 3), lines);
    try checkSnapshot(a, "test/snapshots/report_basic.jsonl", jsonl);
}

test "snapshot: junit diagnostic xml" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = [_]report.Mutant{ mutant(1, .killed, "src/calc.zig", true), mutant(2, .survived, "src/range.zig", false) };
    const xml = try report_junit.render(a, completedReport(&m), false);
    try checkSnapshot(a, "test/snapshots/report_diagnostic.xml", xml);
}

// --- JUnit status mapping ---------------------------------------------------

test "junit status mapping per result status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const killed = [_]report.Mutant{mutant(1, .killed, "src/x.zig", true)};
    try expect(contains(try report_junit.render(a, completedReport(&killed), false), "name=\"status\" value=\"killed\""));

    const compile_error = [_]report.Mutant{mutant(1, .compile_error, "src/x.zig", false)};
    try expect(contains(try report_junit.render(a, completedReport(&compile_error), false), "name=\"status\" value=\"compile_error\""));

    const compiler_crash = [_]report.Mutant{mutant(1, .compiler_crash, "src/x.zig", false)};
    try expect(contains(try report_junit.render(a, completedReport(&compiler_crash), false), "<error type=\"zentinel.compiler_crash\""));

    const survived = [_]report.Mutant{mutant(1, .survived, "src/x.zig", false)};
    const survived_diag = try report_junit.render(a, completedReport(&survived), false);
    try expect(contains(survived_diag, "name=\"status\" value=\"survived\""));
    try expect(!contains(survived_diag, "<failure")); // diagnostic mode: never a failure

    const skipped = [_]report.Mutant{mutant(1, .skipped, "src/x.zig", false)};
    try expect(contains(try report_junit.render(a, completedReport(&skipped), false), "<skipped message=\"deterministically skipped\""));

    const timeout = [_]report.Mutant{mutant(1, .timeout, "src/x.zig", false)};
    try expect(contains(try report_junit.render(a, completedReport(&timeout), false), "<error type=\"zentinel.timeout\""));

    const invalid = [_]report.Mutant{mutant(1, .invalid, "src/x.zig", false)};
    try expect(contains(try report_junit.render(a, completedReport(&invalid), false), "<error type=\"zentinel.invalid\""));

    // Run-level baseline failure: a single `baseline` testcase, no mutant testcases.
    const bf = try report_junit.render(a, baselineFailedReport(), false);
    try expect(contains(bf, "<error type=\"zentinel.baseline_failed\""));
    try expect(contains(bf, "name=\"baseline\""));
}

test "junit renderer replaces XML-illegal control chars from captured evidence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Captured stderr with ANSI-colored compiler output (ESC \x1b) and a BEL
    // (\x07): both are forbidden by XML 1.0, so emitting them verbatim makes a
    // strict CI parser reject the whole testsuite. The renderer must sanitize them
    // while keeping the surrounding text.
    var m = mutant(1, .survived, "src/x.zig", false);
    m.result.evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "error: \x1b[31mboom\x1b[0m\ttab\x07", .failure_summary = "" };
    const ms = [_]report.Mutant{m};
    const xml = try report_junit.render(a, completedReport(&ms), false);

    // No XML-1.0-illegal control byte survives into the output...
    try expect(std.mem.indexOfScalar(u8, xml, 0x1b) == null);
    try expect(std.mem.indexOfScalar(u8, xml, 0x07) == null);
    // ...each illegal byte is replaced by `?`, legal whitespace (tab) is kept, and
    // the legible text is preserved verbatim.
    try expect(contains(xml, "<system-err>error: ?[31mboom?[0m\ttab?</system-err>"));
}

test "junit strict survivor-failing mode emits a failure only for survivors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const survived = [_]report.Mutant{mutant(1, .survived, "src/x.zig", false)};
    const strict = try report_junit.render(a, completedReport(&survived), true);
    try expect(contains(strict, "<failure type=\"zentinel.survived\""));
}

test "junit emits structured command evidence properties" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const killed = [_]report.Mutant{mutant(1, .killed, "src/x.zig", true)};
    const xml = try report_junit.render(a, completedReport(&killed), false);
    for ([_][]const u8{
        "command_count",
        "command_0_original",
        "command_0_argv",
        "command_0_cwd",
        "command_0_environment_policy",
        "command_0_shell",
        "command_0_status",
        "command_0_phase",
    }) |needle| {
        try expect(contains(xml, needle));
    }
}

// --- JSON canonical guarantees ----------------------------------------------

test "json schema compatibility: canonical schema_version and validation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = [_]report.Mutant{mutant(1, .killed, "src/x.zig", true)};
    const rep = completedReport(&m);
    try expectEqual(report.Violation.ok, report.validate(rep));
    const json = try report.toJson(a, rep);
    try expect(contains(json, "\"schema_version\": \"zentinel.report.v1\""));
}

test "summary counts are derived from mutants, not trusted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const m = [_]report.Mutant{ mutant(1, .killed, "src/a.zig", true), mutant(2, .survived, "src/b.zig", false) };
    const derived = report.summarize(&m);
    try expectEqual(@as(u32, 2), derived.total);
    try expectEqual(@as(u32, 1), derived.killed);
    try expectEqual(@as(u32, 1), derived.survived);

    // A manually wrong summary is rejected by the validator.
    var bad = completedReport(&m);
    bad.summary.killed = 5;
    try expectEqual(report.Violation.summary_count_mismatch, report.validate(bad));
}

test "summarize pins every per-status count so a non-kill arm cannot be miscounted as killed" {
    // One mutant per ResultStatus: each status must increment exactly its own
    // bucket. The five non-kill terminal statuses (compile_error/compiler_crash/
    // timeout/skipped/invalid) must stay OUT of killed/survived (I-010), so a
    // regression like `.compile_error => s.killed += 1` -- which validate() cannot
    // catch, being recomputed from the same summarize -- fails here.
    const m = [_]report.Mutant{
        mutant(1, .killed, "src/a.zig", false),
        mutant(2, .survived, "src/b.zig", false),
        mutant(3, .compile_error, "src/c.zig", false),
        mutant(4, .compiler_crash, "src/d.zig", false),
        mutant(5, .timeout, "src/e.zig", false),
        mutant(6, .skipped, "src/f.zig", false),
        mutant(7, .invalid, "src/g.zig", false),
    };
    const s = report.summarize(&m);
    try expectEqual(@as(u64, 7), s.total);
    try expectEqual(@as(u64, 1), s.killed);
    try expectEqual(@as(u64, 1), s.survived);
    try expectEqual(@as(u64, 1), s.compile_error);
    try expectEqual(@as(u64, 1), s.compiler_crash);
    try expectEqual(@as(u64, 1), s.timeout);
    try expectEqual(@as(u64, 1), s.skipped);
    try expectEqual(@as(u64, 1), s.invalid);
}

test "snapshot normalization normalizes durations and ids (I-015)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var m = [_]report.Mutant{mutant(1, .killed, "src/x.zig", true)};
    var rep = completedReport(&m);
    rep.run.duration_ms = 12345; // a nondeterministic wall-clock value

    // JUnit normalizes time to 0 in snapshots; the raw duration never leaks.
    const xml = try report_junit.render(a, rep, false);
    try expect(contains(xml, "time=\"0\""));
    try expect(!contains(xml, "12345"));

    // Canonical JSON normalization replaces run id, started_at, and durations.
    const normalized = try report.normalizeForComparison(a, try report.toJson(a, rep));
    try expect(contains(normalized, "\"<run-id>\""));
    try expect(contains(normalized, "<duration>"));
    try expect(!contains(normalized, "12345"));
}

test "canonical mutant ordering assigns display ids after sorting (I-003)" {
    var m = [_]report.Mutant{ mutant(1, .killed, "src/zzz.zig", false), mutant(1, .survived, "src/aaa.zig", false) };
    report.sortAndAssignDisplayIds(&m);
    // src/aaa.zig sorts before src/zzz.zig; display ids follow the sorted order.
    try expectEqualStrings("src/aaa.zig", m[0].file);
    try expectEqual(@as(u32, 1), m[0].display_id);
    try expectEqualStrings("src/zzz.zig", m[1].file);
    try expectEqual(@as(u32, 2), m[1].display_id);
}

// --- JUnit attribute vs text escaping (numeric refs for \n/\t/\r in attrs) ---

const newline_attr_cmd = [_]report.CommandResult{.{
    .command = .{ .original = "printf 'a\nb'", .argv = &.{ "printf", "a\nb" }, .cwd = "<project>", .environment_policy = .minimal, .shell = false },
    .phase = .mutant,
    .status = .failed,
    .exit_code = 1,
    .timed_out = false,
    .failure_kind = .test_failure,
    .duration_ms = 0,
    .evidence = .{ .stdout_excerpt = "", .stderr_excerpt = "", .failure_summary = "" },
    .skip_reason = null,
}};

test "junit: a newline in an attribute value is numeric-encoded; element text keeps it verbatim" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var m0 = mutant(1, .killed, "src/x.zig", false);
    m0.result.commands = &newline_attr_cmd;
    // An evidence excerpt (element TEXT content) carries the same newline.
    m0.result.evidence = .{ .stdout_excerpt = "line1\nline2", .stderr_excerpt = "", .failure_summary = "" };
    const m = [_]report.Mutant{m0};

    const xml = try report_junit.render(a, completedReport(&m), false);

    // The command_0_original / command_0_argv ATTRIBUTE values carry a newline; it
    // must be a numeric character reference (&#10;), never a raw newline that a
    // conforming parser would silently fold to a space.
    try expect(contains(xml, "command_0_original"));
    try expect(contains(xml, "&#10;"));
    // The <system-out> element TEXT content keeps the raw newline (valid in content).
    try expect(contains(xml, "<system-out>line1\nline2</system-out>"));
}
