const std = @import("std");
const zentinel = @import("zentinel");
const report = zentinel.report;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// The final release dogfood gate (task 085). A release-evidence manifest is a
// passing gate only when every required dogfood/doctest/artifact/recovery gate
// passed with archived or test-verified evidence, repeated dogfood reports are
// deterministic, the protected scope has no invalid mutants, and every protected
// survivor is resolved. This is the executable contract behind
// scripts/release_dogfood_gate.py and the scripts/ci.sh release_dogfood_gate
// stage that runs before task 060 release acceptance.

const required_gates = [_][]const u8{
    "fixture_dogfood",
    "internal_module_dogfood",
    "public_docs_doctest",
    "mutation_aware_doctest",
    "doctest_survivor_ai",
    "pipeline_artifact_validation",
    "failure_recovery_validation",
};
const survivor_resolutions = [_][]const u8{ "fixed_by_test", "equivalent_risk_review" };

fn readFile(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn parse(a: std.mem.Allocator, bytes: []const u8) std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}) catch unreachable;
}

fn objOf(v: std.json.Value) ?std.json.ObjectMap {
    return switch (v) {
        .object => |o| o,
        else => null,
    };
}
fn objOpt(v: ?std.json.Value) ?std.json.ObjectMap {
    return if (v) |x| objOf(x) else null;
}
fn arrOf(v: ?std.json.Value) ?[]std.json.Value {
    const x = v orelse return null;
    return switch (x) {
        .array => |a| a.items,
        else => null,
    };
}
fn gstr(obj: std.json.ObjectMap, key: []const u8) []const u8 {
    const v = obj.get(key) orelse return "";
    return switch (v) {
        .string => |t| t,
        else => "",
    };
}
fn gbool(obj: std.json.ObjectMap, key: []const u8) bool {
    const v = obj.get(key) orelse return false;
    return switch (v) {
        .bool => |b| b,
        else => false,
    };
}
fn gint(obj: std.json.ObjectMap, key: []const u8) i64 {
    const v = obj.get(key) orelse return -1;
    return switch (v) {
        .integer => |n| n,
        else => -1,
    };
}
fn has(set: []const []const u8, x: []const u8) bool {
    for (set) |s| if (std.mem.eql(u8, s, x)) return true;
    return false;
}

/// Structural release-gate validation (no filesystem). Returns true iff `v` is a
/// passing final dogfood gate manifest.
fn releaseGateValid(v: std.json.Value) bool {
    const o = objOf(v) orelse return false;
    if (!std.mem.eql(u8, gstr(o, "schema_version"), "zentinel.release.dogfood_gate.v1")) return false;
    if (gstr(o, "task_id").len == 0) return false;
    if (!std.mem.eql(u8, gstr(o, "status"), "passed")) return false;

    const gates = arrOf(o.get("gates")) orelse return false;
    var seen = [_]bool{false} ** required_gates.len;
    for (gates) |g| {
        const go = objOf(g) orelse return false;
        const name = gstr(go, "name");
        const required = gbool(go, "required");
        if (required) {
            if (!std.mem.eql(u8, gstr(go, "status"), "passed")) return false;
            // A required gate must carry archived report evidence or a test reference.
            if (gstr(go, "report").len == 0 and gstr(go, "verified_by").len == 0) return false;
        }
        for (required_gates, 0..) |rg, i| if (std.mem.eql(u8, rg, name)) {
            seen[i] = true;
        };
    }
    for (seen) |present| if (!present) return false; // every required gate is present

    const rc = objOpt(o.get("repeated_comparison")) orelse return false;
    if (!gbool(rc, "normalized_equal")) return false;

    const ps = objOpt(o.get("protected_scope")) orelse return false;
    if (gint(ps, "invalid_mutants") != 0) return false;
    const survivors = arrOf(ps.get("survivors")) orelse return false;
    for (survivors) |sv| {
        const so = objOf(sv) orelse return false;
        if (!has(&survivor_resolutions, gstr(so, "resolution"))) return false;
        if (gstr(so, "evidence").len == 0) return false;
    }
    return true;
}

fn fileExists(path: []const u8) bool {
    std.Io.Dir.cwd().access(std.testing.io, path, .{}) catch return false;
    return true;
}

// 1. The valid manifest passes and its archived deterministic dogfood evidence
//    exists on disk and normalizes identically across repeated runs.
test "valid release manifest passes with archived deterministic dogfood evidence" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const manifest = parse(arena, try readFile(arena, "test/fixtures/release/valid/release_evidence.json"));
    try expect(releaseGateValid(manifest));

    // Every report-bearing gate and both repeated-comparison runs are archived.
    const o = manifest.object;
    for (o.get("gates").?.array.items) |g| {
        const rep = gstr(g.object, "report");
        if (rep.len > 0) try expect(fileExists(rep));
    }
    const rc = o.get("repeated_comparison").?.object;
    const run_a = gstr(rc, "run_a");
    const run_b = gstr(rc, "run_b");
    try expect(fileExists(run_a));
    try expect(fileExists(run_b));

    // The archived reports differ in raw bytes but normalize identically.
    const a_bytes = try readFile(arena, run_a);
    const b_bytes = try readFile(arena, run_b);
    try expect(!std.mem.eql(u8, a_bytes, b_bytes));
    try expectEqualStrings(
        try report.normalizeForComparison(arena, a_bytes),
        try report.normalizeForComparison(arena, b_bytes),
    );
}

// 2. The gate cannot pass without archived deterministic dogfood evidence or
//    with an invalid mutant, nondeterministic comparison, unresolved survivor,
//    or a missing required gate.
test "final dogfood gate is rejected without complete deterministic evidence" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    inline for (.{
        "missing_dogfood_evidence.json",
        "invalid_mutant.json",
        "nondeterministic.json",
        "unresolved_survivor.json",
        "missing_gate.json",
    }) |name| {
        const path = "test/fixtures/release/invalid/" ++ name;
        const manifest = parse(arena, try readFile(arena, path));
        try expect(!releaseGateValid(manifest));
    }
}

// 3. The archive-existence mechanism actually distinguishes present from absent
//    evidence, so a manifest referencing a missing archive cannot pass.
test "archived dogfood evidence existence is checked" {
    try expect(fileExists("artifacts/pipeline/085/dogfood/run1.report.json"));
    try expect(fileExists("artifacts/pipeline/085/dogfood/run2.report.json"));
    try expect(!fileExists("artifacts/pipeline/085/dogfood/does_not_exist.report.json"));
}

// 4. scripts/ci.sh invokes the final release dogfood gate after the late
//    hardening tasks, and the gate exercises the available sub-gates.
test "scripts/ci.sh exercises the final release dogfood gate" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const ci = try readFile(arena, "scripts/ci.sh");
    try expect(std.mem.indexOf(u8, ci, "release_dogfood_gate") != null);
    try expect(std.mem.indexOf(u8, ci, "scripts/release_dogfood_gate.py") != null);
    // The earlier gates this release gate depends on are still wired.
    try expect(std.mem.indexOf(u8, ci, "pipeline_artifact_validation") != null);
    try expect(std.mem.indexOf(u8, ci, "task_system_validation") != null);
    try expect(std.mem.indexOf(u8, ci, "advisory_dogfood") != null);

    // The release gate script covers the dogfood, artifact, recovery, public-doc
    // doctest, and doctest survivor AI gates available by task 085.
    const gate = try readFile(arena, "scripts/release_dogfood_gate.py");
    inline for (required_gates) |g| try expect(std.mem.indexOf(u8, gate, g) != null);
}

test "release_dogfood_gate reports malformed manifest/fixture JSON instead of crashing (S5)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const gate = try readFile(arena, "scripts/release_dogfood_gate.py");
    // A truncated/corrupt manifest or fixture is a structured gate failure, not an
    // unhandled JSONDecodeError traceback in CI stage 7: json.loads is guarded
    // (_load_json_or_none), main() reports a malformed manifest, and self_test()
    // flags an unparseable fixture (S5).
    try expect(std.mem.indexOf(u8, gate, "_load_json_or_none") != null);
    try expect(std.mem.indexOf(u8, gate, "malformed manifest JSON") != null);
    try expect(std.mem.indexOf(u8, gate, "is not valid JSON") != null);
}
