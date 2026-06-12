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

// The Generator's draw helpers (intRange/boolean/bytes) are public API but had no
// caller or test; intRange also carried a latent overflow -- `hi - lo + 1` and the
// i64 @intCast of the modulo panic for a range spanning more than half the i64
// domain. These pin the bounds (including the full i64 width) and determinism.
test "Generator.intRange stays in bounds for normal, point, and full-width ranges" {
    // Normal range: every draw is within [lo, hi], including negative lo.
    var g = gen.Generator.init(0x123456789ABCDEF);
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const v = g.intRange(-5, 5);
        try std.testing.expect(v >= -5 and v <= 5);
    }

    // A point range lo == hi returns exactly that value.
    var gp = gen.Generator.init(7);
    try std.testing.expectEqual(@as(i64, 42), gp.intRange(42, 42));

    // The full i64 width must neither overflow `hi - lo + 1` nor panic an i64
    // @intCast on the modulo result -- the latent bug. Pre-fix this panics; post-fix
    // every draw is a valid i64 in range.
    var gf = gen.Generator.init(0xDEADBEEF);
    var j: usize = 0;
    while (j < 200) : (j += 1) {
        const v = gf.intRange(std.math.minInt(i64), std.math.maxInt(i64));
        try std.testing.expect(v >= std.math.minInt(i64) and v <= std.math.maxInt(i64));
    }
}

test "Generator.boolean and bytes are deterministic and exercise their range" {
    // boolean(): both values occur over many draws (not a stuck stream).
    var g = gen.Generator.init(0xABCDEF);
    var seen_true = false;
    var seen_false = false;
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        if (g.boolean()) {
            seen_true = true;
        } else {
            seen_false = true;
        }
    }
    try std.testing.expect(seen_true and seen_false);

    // bytes(): a fixed seed fills the whole buffer identically; a different seed
    // produces a different fill (the stream is actually consumed, not left zeroed).
    var a_buf: [37]u8 = undefined;
    var b_buf: [37]u8 = undefined;
    var c_buf: [37]u8 = undefined;
    var ga = gen.Generator.init(0x2024);
    var gb = gen.Generator.init(0x2024);
    var gc = gen.Generator.init(0x2025);
    ga.bytes(&a_buf);
    gb.bytes(&b_buf);
    gc.bytes(&c_buf);
    try std.testing.expectEqualSlices(u8, &a_buf, &b_buf);
    try std.testing.expect(!std.mem.eql(u8, &a_buf, &c_buf));
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

// A FAILED property with a counterexample but shrink status `not_triggered` -- the
// only input that reaches report.zig:172. Otherwise fully valid (status agrees with
// the failed result), so the validate result is attributable solely to the shrink
// status.
const failed_not_triggered_shrink =
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
    \\      "seeds": [1],
    \\      "generator": { "summary": "seeded stream", "generated_cases": 8 },
    \\      "shrinking": { "status": "not_triggered" },
    \\      "result": "failed",
    \\      "counterexample": { "seed": 1, "case": 0 }
    \\    }
    \\  ]
    \\}
;

// The same report with shrink status `unsupported` -- a legitimate failed shrink
// status (shrinking infeasible for the property), so it must validate clean.
const failed_unsupported_shrink =
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
    \\      "seeds": [1],
    \\      "generator": { "summary": "seeded stream", "generated_cases": 8 },
    \\      "shrinking": { "status": "unsupported" },
    \\      "result": "failed",
    \\      "counterexample": { "seed": 1, "case": 0 }
    \\    }
    \\  ]
    \\}
;

test "failed property shrink status: not_triggered is rejected, unsupported is accepted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // not_triggered on a failed property WITH a counterexample is the only path to
    // report.zig:172 -- it must be rejected as failed_without_shrink. Previously no
    // fixture reached this branch, so deleting it passed CI.
    try std.testing.expectEqual(prep.Violation.failed_without_shrink, prep.validate(try parse(a, failed_not_triggered_shrink)));

    // `unsupported` is a legitimate failed shrink status; dropping it from
    // failed_shrink_statuses would misreport this clean report as failed_without_shrink.
    try std.testing.expectEqual(prep.Violation.ok, prep.validate(try parse(a, failed_unsupported_shrink)));
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
//    or weakened with CI staying green.
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

test "property report validator rejects each structural malformation with its specific violation" {
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

// A `properties` item that is not a JSON object.
const bad_property_item_report =
    \\{
    \\  "schema_version": "zentinel.pipeline.property_report.v1",
    \\  "task_id": "062",
    \\  "scope": "property_required",
    \\  "task_class": "high_risk",
    \\  "deterministic": true,
    \\  "status": "passed",
    \\  "properties": [ 42 ]
    \\}
;

// A property whose `name` is empty (present but blank).
const empty_property_name_report =
    \\{
    \\  "schema_version": "zentinel.pipeline.property_report.v1",
    \\  "task_id": "062",
    \\  "scope": "property_required",
    \\  "task_class": "high_risk",
    \\  "deterministic": true,
    \\  "status": "passed",
    \\  "properties": [
    \\    {
    \\      "name": "",
    \\      "invariant": "Determinism",
    \\      "seeds": [1, 2, 3],
    \\      "generator": { "summary": "s", "generated_cases": 256 },
    \\      "shrinking": { "status": "not_triggered" },
    \\      "result": "passed"
    \\    }
    \\  ]
    \\}
;

// A FAILED property that HAS a counterexample but whose shrink status is not a
// terminal one (`not_triggered` is not `minimized`/`unsupported`).
const failed_without_shrink_report =
    \\{
    \\  "schema_version": "zentinel.pipeline.property_report.v1",
    \\  "task_id": "062",
    \\  "scope": "property_required",
    \\  "task_class": "high_risk",
    \\  "deterministic": true,
    \\  "status": "failed",
    \\  "properties": [
    \\    {
    \\      "name": "p",
    \\      "invariant": "Determinism",
    \\      "seeds": [1, 2, 3],
    \\      "generator": { "summary": "s", "generated_cases": 256 },
    \\      "shrinking": { "status": "not_triggered" },
    \\      "result": "failed",
    \\      "counterexample": { "seed": 2, "case": 7 }
    \\    }
    \\  ]
    \\}
;

// The validator has no `zentinel` runtime consumer, so this test is the
// SOLE guard for these rejection branches -- none had a specific-tag assertion
// before, so a regression that swapped or dropped any of them was invisible.
test "property report validator pins per-property and non-object rejection tags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A non-object root (array, scalar, string) is rejected as not_object.
    try std.testing.expectEqual(prep.Violation.not_object, prep.validate(try parse(a, "[]")));
    try std.testing.expectEqual(prep.Violation.not_object, prep.validate(try parse(a, "42")));
    try std.testing.expectEqual(prep.Violation.not_object, prep.validate(try parse(a, "\"x\"")));

    // A non-object `properties` item.
    try std.testing.expectEqual(prep.Violation.bad_property, prep.validate(try parse(a, bad_property_item_report)));
    // A present-but-empty property name.
    try std.testing.expectEqual(prep.Violation.bad_property_name, prep.validate(try parse(a, empty_property_name_report)));
    // A failed property with a counterexample but a non-terminal shrink status.
    try std.testing.expectEqual(prep.Violation.failed_without_shrink, prep.validate(try parse(a, failed_without_shrink_report)));
}

// The full fixture suite: every valid report must be
// accepted and every invalid one rejected. This keeps the validator anchored to
// the frozen contract rather than a handful of hand-picked cases.
const valid_fixtures = [_][]const u8{
    "failed_with_counterexample.json",
    "id_determinism_pass.json",
    "not_property_required_skip.json",
    "ordering_stability_pass.json",
    "scheduler_and_report_rendering_pass.json",
};

// Each invalid fixture is pinned to the EXACT violation it must trigger, not just
// `!= .ok`. Previously this loop asserted only rejection, so the validator (which
// has no product consumer) could regress to returning the WRONG tag -- or a
// fixture could drift to trip a different branch -- with the suite staying green.
const invalid_fixtures = [_]struct { name: []const u8, want: prep.Violation }{
    .{ .name = "bad_invariant_category.json", .want = .bad_invariant },
    .{ .name = "failed_without_counterexample.json", .want = .failed_without_counterexample },
    .{ .name = "high_risk_missing_property_evidence.json", .want = .empty_property_required },
    .{ .name = "missing_generator_summary.json", .want = .missing_generator },
    .{ .name = "missing_invariant.json", .want = .bad_invariant },
    .{ .name = "missing_seed.json", .want = .missing_seeds },
    .{ .name = "missing_shrinking_status.json", .want = .bad_shrinking },
    .{ .name = "status_mismatch.json", .want = .status_mismatch },
};

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

    for (invalid_fixtures) |fx| {
        const path = try std.fmt.allocPrint(a, "test/fixtures/pipeline/property_tests/invalid/{s}", .{fx.name});
        const value = try parse(a, try readFile(a, path));
        const v = prep.validate(value);
        if (v != fx.want) std.debug.print("expected {s} for {s}, got {s}\n", .{ @tagName(fx.want), fx.name, @tagName(v) });
        try std.testing.expectEqual(fx.want, v);
    }
}
