const std = @import("std");
const zentinel = @import("zentinel");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// Release acceptance verification (task 060). This is the final gate: it checks
// the project against docs/PROJECT_ACCEPTANCE_CRITERIA.md from archived,
// deterministic evidence. It implements no product behavior; it verifies that
// the required commands, mutators, reports, schemas, public-doc doctests, the
// final dogfood gate (task 085), network-free CI, advisory-only AI, and the
// AST-stable-default / experimental-opt-in backend policy are all satisfied.
// A release blocker is recorded as a blocked acceptance manifest with concrete
// prerequisite task metadata, never as a passing status.

const required_criteria = [_][]const u8{
    "required_commands",
    "required_mutators",
    "required_reports",
    "schemas_validate_reports",
    "public_docs_doctest",
    "final_dogfood_gate",
    "ci_network_free",
    "ai_advisory_only",
    "ast_stable_default_backends_opt_in",
};

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
fn arrOpt(v: ?std.json.Value) ?[]std.json.Value {
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
fn has(set: []const []const u8, x: []const u8) bool {
    for (set) |s| if (std.mem.eql(u8, s, x)) return true;
    return false;
}
fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}
fn fileExists(path: []const u8) bool {
    std.Io.Dir.cwd().access(std.testing.io, path, .{}) catch return false;
    return true;
}

/// A release acceptance manifest is valid only when its declared `status` agrees
/// with the criteria and blockers: `passed` requires every criterion passed and
/// no blockers; `blocked` requires at least one unmet criterion or blocker.
fn acceptanceValid(v: std.json.Value) bool {
    const o = objOf(v) orelse return false;
    if (!std.mem.eql(u8, gstr(o, "schema_version"), "zentinel.release.acceptance.v1")) return false;
    if (gstr(o, "task_id").len == 0) return false;
    const status = gstr(o, "status");
    if (!std.mem.eql(u8, status, "passed") and !std.mem.eql(u8, status, "blocked")) return false;

    const criteria = arrOpt(o.get("criteria")) orelse return false;
    var seen = [_]bool{false} ** required_criteria.len;
    var all_passed = true;
    for (criteria) |c| {
        const co = objOf(c) orelse return false;
        const id = gstr(co, "id");
        const cstatus = gstr(co, "status");
        if (gstr(co, "evidence").len == 0) return false;
        if (!has(&[_][]const u8{ "passed", "failed", "blocked" }, cstatus)) return false;
        if (!std.mem.eql(u8, cstatus, "passed")) all_passed = false;
        for (required_criteria, 0..) |rc, i| if (std.mem.eql(u8, rc, id)) {
            seen[i] = true;
        };
    }
    for (seen) |present| if (!present) return false;

    const blockers = arrOpt(o.get("blockers")) orelse return false;
    const no_blockers = blockers.len == 0;

    if (std.mem.eql(u8, status, "passed")) {
        return all_passed and no_blockers;
    }
    // status == "blocked": there must be a real reason to block.
    return !(all_passed and no_blockers);
}

// 1. The valid acceptance manifest passes; manifests that hide an unmet
//    criterion or a blocker behind a passing status are rejected.
test "release acceptance manifest agrees status with criteria and blockers" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const valid = parse(arena, try readFile(arena, "test/fixtures/release/valid/acceptance.json"));
    try expect(acceptanceValid(valid));

    inline for (.{
        "acceptance_unmet_criterion.json",
        "acceptance_blocker_ignored.json",
    }) |name| {
        const m = parse(arena, try readFile(arena, "test/fixtures/release/invalid/" ++ name));
        try expect(!acceptanceValid(m));
    }
}

// 2. The final dogfood gate evidence from task 085 exists.
test "final dogfood gate evidence from task 085 exists" {
    try expect(fileExists("artifacts/pipeline/085/dogfood/run1.report.json"));
    try expect(fileExists("artifacts/pipeline/085/dogfood/run2.report.json"));
    try expect(fileExists("artifacts/pipeline/085/dogfood/survivor_review.md"));
    try expect(fileExists("artifacts/pipeline/085/verification/report.json"));
}

// 3. AST remains the stable default and experimental backends remain opt-in.
test "AST is the stable default and experimental backends are opt-in" {
    try expect(contains(zentinel.default_config, "default = \"ast\""));
    try expect(contains(zentinel.default_config, "experimental = []"));
}

// 4. Every required command is reachable from the deterministic help text and CLI.
test "required commands appear in the help text" {
    inline for (.{
        "init",    "version", "check",   "list-mutants", "run",
        "doctest", "explain", "suggest", "review-tests",
    }) |cmd| try expect(contains(zentinel.help_text, cmd));
}

// 5. The required stable mutators are all present in the deterministic core.
test "required stable mutators are accessible" {
    _ = zentinel.mutators.arithmetic;
    _ = zentinel.mutators.comparison;
    _ = zentinel.mutators.logical;
    _ = zentinel.mutators.boolean;
    _ = zentinel.mutators.optional;
    _ = zentinel.mutators.error_path;
    _ = zentinel.mutators.integer_boundary;
    _ = zentinel.mutators.loop_boundary;
}

// 6. The release acceptance checklist script and the CI entrypoint wire the
//    final release gates that this acceptance verifies.
test "release acceptance checklist script and CI exercise the release gates" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const ci = try readFile(arena, "scripts/ci.sh");
    try expect(contains(ci, "release_dogfood_gate"));

    const acc = try readFile(arena, "scripts/release_acceptance.py");
    inline for (required_criteria) |c| try expect(contains(acc, c));
    // The acceptance check runs the final dogfood gate from task 085.
    try expect(contains(acc, "release_dogfood_gate.py"));
}

// 7. The final_dogfood_gate criterion must reflect verified_by script EXECUTION,
//    not just on-disk existence. check_criteria validates the manifest with
//    execute_checks=True (matching the rdg.main() path), so a verified_by script
//    that exists but exits non-zero fails the criterion instead of printing
//    "final_dogfood_gate: OK" before rdg.main() reports the real failure (L34).
test "release acceptance gate criterion executes verified_by checks, not just existence (L34)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const acc = try readFile(arena, "scripts/release_acceptance.py");
    // The gate_clean computation runs the verified_by scripts; the existence-only
    // default (execute_checks=False) -- the bug -- is gone.
    try expect(contains(acc, "execute_checks=True"));
    // It is still the archive-checked validate_manifest call that computes gate_clean.
    try expect(contains(acc, "check_archives=True"));
}
