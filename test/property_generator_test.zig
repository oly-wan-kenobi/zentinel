const std = @import("std");
const zentinel = @import("zentinel");
const gen = zentinel.property.generator;
const prep = zentinel.property.report;
const support = @import("support/property.zig");

fn parse(a: std.mem.Allocator, bytes: []const u8) !std.json.Value {
    return (try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}));
}

fn readFile(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

// ---------------------------------------------------------------------------
// 1. Determinism: the same seed emits the same generated case sequence.
// ---------------------------------------------------------------------------
test "same seed emits the same generated case sequence" {
    var g1 = gen.Generator.init(0xC0FFEE);
    var g2 = gen.Generator.init(0xC0FFEE);
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try std.testing.expectEqual(g1.next(), g2.next());
    }

    // A different seed must diverge within a short prefix (not a constant stream).
    var same = gen.Generator.init(0xC0FFEE);
    var other = gen.Generator.init(0xC0FFEF);
    var diverged = false;
    i = 0;
    while (i < 16) : (i += 1) {
        if (same.next() != other.next()) {
            diverged = true;
            break;
        }
    }
    try std.testing.expect(diverged);
}

// The support helper runs a property over a seeded stream and records the seed,
// the generated case count, and a counterexample on failure — deterministically.
test "property support helper records seed and generated case count deterministically" {
    const run_a = support.forAllU64(99, 64, struct {
        fn f(_: u64) bool {
            return true;
        }
    }.f);
    try std.testing.expect(run_a.passed);
    try std.testing.expectEqual(@as(u64, 99), run_a.seed);
    try std.testing.expectEqual(@as(u64, 64), run_a.generated_cases);
    try std.testing.expectEqual(@as(?u64, null), run_a.counterexample);

    // A property that rejects odd draws stops at the first failing case and
    // records it; the same seed reproduces the same counterexample exactly.
    const fail_1 = support.forAllU64(99, 64, struct {
        fn f(x: u64) bool {
            return x % 2 == 0;
        }
    }.f);
    const fail_2 = support.forAllU64(99, 64, struct {
        fn f(x: u64) bool {
            return x % 2 == 0;
        }
    }.f);
    try std.testing.expect(!fail_1.passed);
    try std.testing.expect(fail_1.counterexample != null);
    try std.testing.expectEqual(fail_1.counterexample, fail_2.counterexample);
    try std.testing.expectEqual(fail_1.generated_cases, fail_2.generated_cases);
}

// ---------------------------------------------------------------------------
// 2. A failed property report records seed, invariant, generated count, and
//    shrink status; the validator rejects a failed report missing them.
// ---------------------------------------------------------------------------
const failed_report =
    \\{
    \\  "schema_version": "zentinel.pipeline.property_report.v1",
    \\  "task_id": "062",
    \\  "scope": "property_required",
    \\  "task_class": "high_risk",
    \\  "deterministic": true,
    \\  "status": "failed",
    \\  "properties": [
    \\    {
    \\      "name": "generator_is_deterministic",
    \\      "invariant": "Determinism",
    \\      "seeds": [1, 2, 3],
    \\      "generator": { "summary": "seeded splitmix64 stream", "generated_cases": 256 },
    \\      "shrinking": { "status": "minimized" },
    \\      "result": "failed",
    \\      "counterexample": { "seed": 2, "case": 7 }
    \\    }
    \\  ]
    \\}
;

test "a failed property report records seed, invariant, generated count, and shrink status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A failed report that records every mandatory field — seed list, invariant
    // category, generated case count, shrink status, and a minimized
    // counterexample — is accepted. The rejection paths are covered below.
    const value = try parse(a, failed_report);
    try std.testing.expectEqual(prep.Violation.ok, prep.validate(value));

    const prop = value.object.get("properties").?.array.items[0].object;
    try std.testing.expect(prop.get("seeds").?.array.items.len > 0);
    try std.testing.expect(prop.get("invariant").?.string.len > 0);
    try std.testing.expect(prop.get("generator").?.object.get("generated_cases") != null);
    try std.testing.expect(prop.get("shrinking").?.object.get("status") != null);
}

// A failed property without a minimized counterexample is rejected.
const failed_no_counterexample =
    \\{
    \\  "schema_version": "zentinel.pipeline.property_report.v1",
    \\  "task_id": "062",
    \\  "scope": "property_required",
    \\  "task_class": "high_risk",
    \\  "deterministic": true,
    \\  "status": "failed",
    \\  "properties": [
    \\    {
    \\      "name": "generator_is_deterministic",
    \\      "invariant": "Determinism",
    \\      "seeds": [1, 2, 3],
    \\      "generator": { "summary": "seeded splitmix64 stream", "generated_cases": 256 },
    \\      "shrinking": { "status": "not_triggered" },
    \\      "result": "failed",
    \\      "counterexample": null
    \\    }
    \\  ]
    \\}
;

test "a failed property without a minimized counterexample is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const value = try parse(a, failed_no_counterexample);
    try std.testing.expectEqual(prep.Violation.failed_without_counterexample, prep.validate(value));
}

// status must equal "failed" iff some property failed.
const status_mismatch =
    \\{
    \\  "schema_version": "zentinel.pipeline.property_report.v1",
    \\  "task_id": "062",
    \\  "scope": "property_required",
    \\  "task_class": "high_risk",
    \\  "deterministic": true,
    \\  "status": "passed",
    \\  "properties": [
    \\    {
    \\      "name": "generator_is_deterministic",
    \\      "invariant": "Determinism",
    \\      "seeds": [1],
    \\      "generator": { "summary": "seeded stream", "generated_cases": 8 },
    \\      "shrinking": { "status": "minimized" },
    \\      "result": "failed",
    \\      "counterexample": { "seed": 1, "case": 0 }
    \\    }
    \\  ]
    \\}
;

test "report status must agree with property results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const value = try parse(a, status_mismatch);
    try std.testing.expectEqual(prep.Violation.status_mismatch, prep.validate(value));
}

// ---------------------------------------------------------------------------
// 3. Missing property evidence on a high-risk task is rejected; the valid
//    not-property-required skip fixture is accepted.
// ---------------------------------------------------------------------------
test "missing property evidence on a high-risk task is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = try readFile(a, "test/fixtures/pipeline/property_tests/invalid/high_risk_missing_property_evidence.json");
    const value = try parse(a, bytes);
    try std.testing.expectEqual(prep.Violation.empty_property_required, prep.validate(value));
}

test "a not-property-required skip report is accepted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = try readFile(a, "test/fixtures/pipeline/property_tests/valid/not_property_required_skip.json");
    const value = try parse(a, bytes);
    try std.testing.expectEqual(prep.Violation.ok, prep.validate(value));
}

// ---------------------------------------------------------------------------
// 4. Top-of-funnel structural guards each return their SPECIFIC violation. All
//    committed invalid fixtures carry a valid schema_version/scope/task_class/
//    status, so these first-line checks had no negative test and could be deleted
//    or weakened with CI staying green (L3).
// ---------------------------------------------------------------------------
const bad_result_report =
    \\{
    \\  "schema_version": "zentinel.pipeline.property_report.v1",
    \\  "task_id": "062",
    \\  "scope": "property_required",
    \\  "task_class": "high_risk",
    \\  "deterministic": true,
    \\  "status": "passed",
    \\  "properties": [
    \\    {
    \\      "name": "p",
    \\      "invariant": "Determinism",
    \\      "seeds": [1, 2, 3],
    \\      "generator": { "summary": "s", "generated_cases": 256 },
    \\      "shrinking": { "status": "not_triggered" },
    \\      "result": "maybe"
    \\    }
    \\  ]
    \\}
;

test "property report validator rejects each structural malformation with its specific violation (L3)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The unmutated baseline validates clean, so each rejection below is
    // attributable to the single mutation applied.
    try std.testing.expectEqual(prep.Violation.ok, prep.validate(try parse(a, failed_report)));

    {
        var v = try parse(a, failed_report);
        try v.object.put(a, "schema_version", .{ .string = "zentinel.pipeline.property_report.v2" });
        try std.testing.expectEqual(prep.Violation.bad_schema_version, prep.validate(v));
    }
    {
        var v = try parse(a, failed_report);
        try v.object.put(a, "scope", .{ .string = "bogus_scope" });
        try std.testing.expectEqual(prep.Violation.bad_scope, prep.validate(v));
    }
    {
        var v = try parse(a, failed_report);
        try v.object.put(a, "task_class", .{ .string = "bogus_class" });
        try std.testing.expectEqual(prep.Violation.bad_task_class, prep.validate(v));
    }
    {
        var v = try parse(a, failed_report);
        _ = v.object.orderedRemove("task_id");
        try std.testing.expectEqual(prep.Violation.missing_field, prep.validate(v));
    }
    {
        // A non-bool `deterministic` is structurally invalid (must be a JSON bool).
        var v = try parse(a, failed_report);
        try v.object.put(a, "deterministic", .{ .integer = 1 });
        try std.testing.expectEqual(prep.Violation.missing_field, prep.validate(v));
    }
    {
        var v = try parse(a, failed_report);
        _ = v.object.orderedRemove("properties");
        try std.testing.expectEqual(prep.Violation.missing_field, prep.validate(v));
    }
    {
        var v = try parse(a, failed_report);
        try v.object.put(a, "status", .{ .string = "bogus_status" });
        try std.testing.expectEqual(prep.Violation.bad_status, prep.validate(v));
    }
    {
        // not_property_required scope with NO skip_reason (failed_report has none).
        var v = try parse(a, failed_report);
        try v.object.put(a, "scope", .{ .string = "not_property_required" });
        try std.testing.expectEqual(prep.Violation.missing_skip_reason, prep.validate(v));
    }
    {
        // not_property_required scope with an EMPTY skip_reason.
        var v = try parse(a, failed_report);
        try v.object.put(a, "scope", .{ .string = "not_property_required" });
        try v.object.put(a, "skip_reason", .{ .string = "" });
        try std.testing.expectEqual(prep.Violation.missing_skip_reason, prep.validate(v));
    }
    // A bad per-property `result` string (the nested first-line result guard).
    try std.testing.expectEqual(prep.Violation.bad_result, prep.validate(try parse(a, bad_result_report)));
}

// The full fixture suite shipped by task 044: every valid report must be
// accepted and every invalid one rejected. This keeps the validator anchored to
// the frozen contract rather than only the three cases the task spec calls out.
const valid_fixtures = [_][]const u8{
    "failed_with_counterexample.json",
    "id_determinism_pass.json",
    "not_property_required_skip.json",
    "ordering_stability_pass.json",
    "scheduler_and_report_rendering_pass.json",
};

const invalid_fixtures = [_][]const u8{
    "bad_invariant_category.json",
    "failed_without_counterexample.json",
    "high_risk_missing_property_evidence.json",
    "missing_generator_summary.json",
    "missing_invariant.json",
    "missing_seed.json",
    "missing_shrinking_status.json",
    "status_mismatch.json",
};

// The property evidence task 062 itself emits must satisfy the contract it
// implements — this is the integration point between generated property
// evidence and the pipeline verification artifacts.
test "the task 062 property artifact is contract-valid" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = try readFile(a, "artifacts/pipeline/062/property/report.json");
    const value = try parse(a, bytes);
    try std.testing.expectEqual(prep.Violation.ok, prep.validate(value));
}

test "every valid property fixture is accepted and every invalid one rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    for (valid_fixtures) |name| {
        const path = try std.fmt.allocPrint(a, "test/fixtures/pipeline/property_tests/valid/{s}", .{name});
        const value = try parse(a, try readFile(a, path));
        const v = prep.validate(value);
        if (v != .ok) std.debug.print("expected ok for {s}, got {s}\n", .{ name, @tagName(v) });
        try std.testing.expectEqual(prep.Violation.ok, v);
    }

    for (invalid_fixtures) |name| {
        const path = try std.fmt.allocPrint(a, "test/fixtures/pipeline/property_tests/invalid/{s}", .{name});
        const value = try parse(a, try readFile(a, path));
        const v = prep.validate(value);
        if (v == .ok) std.debug.print("expected rejection for {s}\n", .{name});
        try std.testing.expect(v != .ok);
    }
}
