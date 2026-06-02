// Layer: deterministic_core
//
// Structural validator for the property-test report contract
// `zentinel.pipeline.property_report.v1` (docs/PROPERTY_TEST_POLICY.md, task
// 062). Task 044 froze the report shape and shipped example artifacts; this
// module is the in-tree executable check that distinguishes passing property
// evidence from missing or malformed evidence.
//
// Consumer scope: this is a pipeline/verification helper with NO `zentinel`
// runtime consumer -- no CLI verb calls `validate()`, and it never participates
// in a mutation run. The property_report contract is enforced out of band by the
// pipeline tooling (scripts/validate_task_system.py / CI) and pinned in-tree by
// test/property_generator_test.zig, which asserts the EXACT `Violation` tag for
// every rejection branch so a regression in this validator is caught even though
// no product path exercises it (L13).
//
// The validator is pure and deterministic: it inspects a parsed `std.json.Value`
// and returns the first contract violation it finds, or `.ok`. It never calls
// AI, never touches the filesystem, and never decides a mutant's classification.
const std = @import("std");

pub const schema_version = "zentinel.pipeline.property_report.v1";

/// The mandatory invariant categories every property must declare
/// (docs/PROPERTY_TEST_POLICY.md "Mandatory Invariant Categories").
pub const mandatory_invariants = [_][]const u8{
    "Determinism",
    "Stability",
    "Round-trip",
    "Isolation",
    "Monotonicity",
    "Collision resistance",
};

const scopes = [_][]const u8{ "property_required", "not_property_required" };
const task_classes = [_][]const u8{ "high_risk", "low_risk", "normal", "compiler_internal" };
const shrink_statuses = [_][]const u8{ "not_triggered", "minimized", "unsupported" };
const failed_shrink_statuses = [_][]const u8{ "minimized", "unsupported" };

/// The first contract violation found, or `.ok`. Tags are stable so callers and
/// tests can assert the precise failure mode.
pub const Violation = enum {
    ok,
    not_object,
    bad_schema_version,
    missing_field,
    bad_scope,
    bad_task_class,
    bad_status,
    empty_property_required,
    missing_skip_reason,
    bad_property,
    bad_property_name,
    bad_invariant,
    missing_seeds,
    missing_generator,
    bad_shrinking,
    bad_result,
    failed_without_counterexample,
    failed_without_shrink,
    status_mismatch,
};

fn asObject(v: std.json.Value) ?std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
        else => null,
    };
}

fn getStr(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .string => |s| s,
        else => null,
    };
}

fn isOneOf(s: []const u8, set: []const []const u8) bool {
    for (set) |item| {
        if (std.mem.eql(u8, s, item)) return true;
    }
    return false;
}

/// Validate a parsed property report against
/// `zentinel.pipeline.property_report.v1`.
pub fn validate(value: std.json.Value) Violation {
    const root = asObject(value) orelse return .not_object;

    const sv = getStr(root, "schema_version") orelse return .bad_schema_version;
    if (!std.mem.eql(u8, sv, schema_version)) return .bad_schema_version;

    _ = getStr(root, "task_id") orelse return .missing_field;

    const scope = getStr(root, "scope") orelse return .bad_scope;
    if (!isOneOf(scope, &scopes)) return .bad_scope;

    const task_class = getStr(root, "task_class") orelse return .bad_task_class;
    if (!isOneOf(task_class, &task_classes)) return .bad_task_class;

    const det = root.get("deterministic") orelse return .missing_field;
    switch (det) {
        .bool => {},
        else => return .missing_field,
    }

    const status = getStr(root, "status") orelse return .bad_status;
    const status_failed = std.mem.eql(u8, status, "failed");
    if (!status_failed and !std.mem.eql(u8, status, "passed")) return .bad_status;

    const props_v = root.get("properties") orelse return .missing_field;
    const props = switch (props_v) {
        .array => |arr| arr,
        else => return .missing_field,
    };

    const property_required = std.mem.eql(u8, scope, "property_required");
    if (property_required and props.items.len == 0) return .empty_property_required;
    if (!property_required) {
        const reason = getStr(root, "skip_reason") orelse return .missing_skip_reason;
        if (reason.len == 0) return .missing_skip_reason;
    }

    var any_failed = false;
    for (props.items) |pv| {
        const prop = asObject(pv) orelse return .bad_property;

        const name = getStr(prop, "name") orelse return .bad_property_name;
        if (name.len == 0) return .bad_property_name;

        const invariant = getStr(prop, "invariant") orelse return .bad_invariant;
        if (!isOneOf(invariant, &mandatory_invariants)) return .bad_invariant;

        // Explicit, non-empty seed list (never silently generated).
        const seeds_v = prop.get("seeds") orelse return .missing_seeds;
        const seeds = switch (seeds_v) {
            .array => |arr| arr,
            else => return .missing_seeds,
        };
        if (seeds.items.len == 0) return .missing_seeds;
        for (seeds.items) |s| switch (s) {
            .integer => {},
            else => return .missing_seeds,
        };

        // Generator summary including a generated case count.
        const gen_v = prop.get("generator") orelse return .missing_generator;
        const gen_obj = asObject(gen_v) orelse return .missing_generator;
        const summary = getStr(gen_obj, "summary") orelse return .missing_generator;
        if (summary.len == 0) return .missing_generator;
        const generated_cases = gen_obj.get("generated_cases") orelse return .missing_generator;
        switch (generated_cases) {
            .integer => {},
            else => return .missing_generator,
        }

        // Shrink status from the allowed set.
        const shrink_v = prop.get("shrinking") orelse return .bad_shrinking;
        const shrink_obj = asObject(shrink_v) orelse return .bad_shrinking;
        const shrink_status = getStr(shrink_obj, "status") orelse return .bad_shrinking;
        if (!isOneOf(shrink_status, &shrink_statuses)) return .bad_shrinking;

        const result = getStr(prop, "result") orelse return .bad_result;
        const result_failed = std.mem.eql(u8, result, "failed");
        if (!result_failed and !std.mem.eql(u8, result, "passed")) return .bad_result;

        if (result_failed) {
            const ce = prop.get("counterexample");
            const has_counterexample = ce != null and ce.? != .null;
            if (!has_counterexample) return .failed_without_counterexample;
            if (!isOneOf(shrink_status, &failed_shrink_statuses)) return .failed_without_shrink;
            any_failed = true;
        }
    }

    // The report status is derived, not asserted: failed iff a property failed.
    if (status_failed != any_failed) return .status_mismatch;

    return .ok;
}
