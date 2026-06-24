//! Real JSON-Schema validation of rendered report output.
//!
//! docs/REPORT_FORMAT.md describes JSON-Schema validation of reports. This file
//! wires schemas/report.v1.schema.json (and schemas/doctest.report.v1.schema.json)
//! into the test suite via the dependency-free validator in
//! test/support/json_schema.zig.
//!
//! report.v1 coverage is thorough: representative `completed` and
//! `baseline_failed` reports are built from the same `report.Report` struct
//! style as report_schema_test.zig, rendered through the real renderer, parsed
//! to `std.json.Value`, and asserted VALID; the embedded minimal snapshot is
//! validated too; and a negative test mutates a rendered report (dropping a
//! required field and corrupting an enum value) to prove the validator rejects
//! malformed reports.
//!
//! doctest.report.v1 scope: rather than reconstruct the doctest renderer's
//! struct graph here, a representative doctest report (one ordinary `zig_test`
//! case plus one `mutation`/`survived` case) is authored inline and validated.
//! This exercises the doctest-only schema keywords the report.v1 schema does
//! not use -- `oneOf`, `not`, and `$defs` resolution across `case`,
//! `case_mutation`, `mutation_runner_evidence`, `result`, and `snapshot`.

const std = @import("std");
const zentinel = @import("zentinel");
const report = zentinel.report;
const json_schema = @import("support/json_schema.zig");

const expect = std.testing.expect;

const minimal_snapshot = @embedFile("snapshots/report_minimal.json");

fn readJson(a: std.mem.Allocator, path: []const u8) !std.json.Value {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
    return std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{});
}

fn parseJson(a: std.mem.Allocator, src: []const u8) !std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, a, src, .{});
}

// --- Reusable report components (mirrors report_schema_test.zig) ------------

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

fn baselineFailedReport() report.Report {
    return .{
        .run = baseRun(.baseline_failed, null),
        .baseline = .{ .status = .failed, .commands = &failed_baseline_commands },
        .summary = .{},
        .mutants = &no_mutants,
    };
}

fn renderAndParse(a: std.mem.Allocator, r: report.Report) !std.json.Value {
    const bytes = try report.toJson(a, r);
    return parseJson(a, bytes);
}

// --- report.v1 positive validation -----------------------------------------

test "rendered completed report (with a mutant) validates against report.v1 schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/report.v1.schema.json");
    const instance = try renderAndParse(a, completedReport(&one_mutant));
    try expect(json_schema.validate(schema, instance, schema));
}

test "rendered completed report (empty mutants) validates against report.v1 schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/report.v1.schema.json");
    const instance = try renderAndParse(a, completedReport(&no_mutants));
    try expect(json_schema.validate(schema, instance, schema));
}

test "rendered baseline_failed report validates against report.v1 schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/report.v1.schema.json");
    const instance = try renderAndParse(a, baselineFailedReport());
    try expect(json_schema.validate(schema, instance, schema));
}

test "embedded minimal snapshot validates against report.v1 schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/report.v1.schema.json");
    const instance = try parseJson(a, minimal_snapshot);
    try expect(json_schema.validate(schema, instance, schema));
}

// --- report.v1 negative validation (the validator has teeth) ----------------

test "validator rejects a report missing a required field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/report.v1.schema.json");

    const instance = try renderAndParse(a, completedReport(&one_mutant));
    try expect(json_schema.validate(schema, instance, schema));

    // Drop a required field (run.id) -> run.required ["id", ...] must fail.
    _ = instance.object.getPtr("run").?.object.orderedRemove("id");
    try expect(!json_schema.validate(schema, instance, schema));
}

test "validator rejects a report with a bad enum value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/report.v1.schema.json");

    const instance = try renderAndParse(a, completedReport(&one_mutant));
    try expect(json_schema.validate(schema, instance, schema));

    // Corrupt the mutant backend enum: "ast"/"zir" only.
    const mutant = &instance.object.getPtr("mutants").?.array.items[0];
    try mutant.object.put(a, "backend", .{ .string = "bogus_backend" });
    try expect(!json_schema.validate(schema, instance, schema));
}

test "validator rejects an unexpected additional property (closed object)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/report.v1.schema.json");

    const instance = try renderAndParse(a, completedReport(&no_mutants));
    try expect(json_schema.validate(schema, instance, schema));

    // additionalProperties:false at the top level forbids unknown keys.
    try instance.object.put(a, "unexpected", .{ .bool = true });
    try expect(!json_schema.validate(schema, instance, schema));
}

test "validator rejects a config_hash that violates its pattern" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/report.v1.schema.json");

    const instance = try renderAndParse(a, completedReport(&no_mutants));
    try expect(json_schema.validate(schema, instance, schema));

    // Pattern: ^sha256:[a-fA-F0-9]{64}$ -- a short hex tail must be rejected.
    try instance.object.getPtr("run").?.object.put(a, "config_hash", .{ .string = "sha256:deadbeef" });
    try expect(!json_schema.validate(schema, instance, schema));
}

// --- doctest.report.v1 validation -------------------------------------------

const doctest_report_json =
    \\{
    \\  "schema_version": "zentinel.doctest.report.v1",
    \\  "run": {
    \\    "id": "run_doctest_0000",
    \\    "status": "completed",
    \\    "error": null,
    \\    "zentinel_version": "0.1.0",
    \\    "zig_version": "0.16.0",
    \\    "command": "zentinel doctest",
    \\    "project_root": "<project>",
    \\    "started_at": "<normalized>",
    \\    "duration_ms": 0
    \\  },
    \\  "summary": {
    \\    "total": 1,
    \\    "passed": 1,
    \\    "failed": 0,
    \\    "compile_error": 0,
    \\    "expected_compile_error": 0,
    \\    "timeout": 0,
    \\    "skipped": 0,
    \\    "invalid": 0
    \\  },
    \\  "cases": [
    \\    {
    \\      "id": "dt_0123456789abcdefghjkmnpqrs",
    \\      "file": "docs/EXAMPLE.md",
    \\      "line_start": 1,
    \\      "line_end": 4,
    \\      "source_ref": "ds_0123456789abcdefghjkmnpqrs",
    \\      "block_refs": [],
    \\      "kind": "zig_test",
    \\      "status": "passed",
    \\      "expectation": null,
    \\      "command": {
    \\        "original": "zig test x.zig",
    \\        "argv": ["zig", "test", "x.zig"],
    \\        "cwd": "<project>",
    \\        "environment_policy": "minimal",
    \\        "shell": false
    \\      },
    \\      "result": {
    \\        "exit_code": 0,
    \\        "timed_out": false,
    \\        "duration_ms": 0,
    \\        "stdout_excerpt": "",
    \\        "stderr_excerpt": "",
    \\        "normalized_stdout_excerpt": "",
    \\        "normalized_stderr_excerpt": "",
    \\        "snapshot": null,
    \\        "failure_summary": ""
    \\      },
    \\      "diagnostics": [],
    \\      "advisory": { "ai": null }
    \\    },
    \\    {
    \\      "id": "dm_0123456789abcdefghjkmnpqrs",
    \\      "file": "docs/EXAMPLE.md",
    \\      "line_start": 6,
    \\      "line_end": 9,
    \\      "source_ref": "ds_0123456789abcdefghjkmnpqrs",
    \\      "block_refs": [],
    \\      "kind": "mutation",
    \\      "status": "survived",
    \\      "expectation": null,
    \\      "command": null,
    \\      "result": null,
    \\      "diagnostics": [],
    \\      "advisory": { "ai": null },
    \\      "mutation": {
    \\        "doctest_case_id": "dt_0123456789abcdefghjkmnpqrs",
    \\        "mutant_id": "m_0123",
    \\        "operator": "comparison_boundary",
    \\        "operator_stability": "stable",
    \\        "backend": "ast",
    \\        "backend_stability": "stable",
    \\        "doc_file": "docs/EXAMPLE.md",
    \\        "doc_line": 6,
    \\        "source_ref": "ds_0123456789abcdefghjkmnpqrs",
    \\        "mutated_diff": ["-a", "+b"],
    \\        "survivor_ref": "ds_0123456789abcdefghjkmnpqrs",
    \\        "runner_evidence": {
    \\          "status": "survived",
    \\          "command": {
    \\            "original": "zig test x.zig",
    \\            "argv": ["zig", "test", "x.zig"],
    \\            "cwd": "<project>",
    \\            "environment_policy": "minimal",
    \\            "shell": false
    \\          },
    \\          "exit_code": 0,
    \\          "timed_out": false,
    \\          "failure_kind": "none",
    \\          "stdout_excerpt": "",
    \\          "stderr_excerpt": "",
    \\          "failure_summary": "",
    \\          "skip_reason": null
    \\        }
    \\      }
    \\    }
    \\  ]
    \\}
;

test "representative doctest report validates against doctest.report.v1 schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/doctest.report.v1.schema.json");
    const instance = try parseJson(a, doctest_report_json);
    try expect(json_schema.validate(schema, instance, schema));
}

test "validator rejects a survived mutation case missing its survivor_ref" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = try readJson(a, "schemas/doctest.report.v1.schema.json");

    const instance = try parseJson(a, doctest_report_json);
    try expect(json_schema.validate(schema, instance, schema));

    // For kind="mutation"+status="survived", mutation.survivor_ref must be a
    // non-null ds_ string (conditional `if`/`then` plus `oneOf`/`not`). Setting
    // it to null violates the survived branch.
    const mutation = instance.object.getPtr("cases").?.array.items[1].object.getPtr("mutation").?;
    try mutation.object.put(a, "survivor_ref", .{ .null = {} });
    try expect(!json_schema.validate(schema, instance, schema));
}
