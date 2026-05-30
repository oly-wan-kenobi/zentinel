const std = @import("std");
const zentinel = @import("zentinel");

const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;
const optional = zentinel.mutators.optional;
const error_path = zentinel.mutators.error_path;
const integer_boundary = zentinel.mutators.integer_boundary;
const loop_boundary = zentinel.mutators.loop_boundary;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const fixture_path = "test/fixtures/dogfood/semantic/sample.zig";

fn readFixture(a: std.mem.Allocator) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, fixture_path, a, std.Io.Limit.limited(1 << 20));
}

// Stage-2 dogfood: run every stable Phase 2 semantic recognizer over the
// semantic fixture through the shared collector (the Phase 2 recognizers are not
// yet wired into `zentinel run`, so the dogfood drives them directly).
fn collectPhase2(a: std.mem.Allocator, parsed: ast_backend.Parsed) ![]mutant.Mutant {
    var collector = ast_backend.Collector.init(a);
    const test_ranges = try ast_backend.testDeclRanges(parsed, a);
    try optional.collect(&collector, parsed, fixture_path, test_ranges);
    try error_path.collect(&collector, parsed, fixture_path, test_ranges);
    try integer_boundary.collect(&collector, parsed, fixture_path, test_ranges);
    try loop_boundary.collect(&collector, parsed, fixture_path, test_ranges);
    return collector.finish();
}

fn has(c: []const mutant.Mutant, op: []const u8) bool {
    for (c) |m| {
        if (std.mem.eql(u8, m.operator, op)) return true;
    }
    return false;
}

test "phase 2 semantic dogfood: every stable mutator fires over the fixture" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a);
    var parsed = try ast_backend.parse(std.testing.allocator, fixture_path, src);
    defer parsed.deinit();
    const c = try collectPhase2(a, parsed);

    try expect(c.len > 0);
    for ([_][]const u8{
        "optional_orelse_unreachable",
        "optional_null_check",
        "error_catch_unreachable",
        "errdefer_remove",
        "integer_literal_boundary",
        "loop_boundary",
    }) |op| {
        try expect(has(c, op));
    }
}

test "phase 2 semantic dogfood: no invalid mutants in the stable fixture scope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a);
    var parsed = try ast_backend.parse(std.testing.allocator, fixture_path, src);
    defer parsed.deinit();
    const c = try collectPhase2(a, parsed);

    // Every candidate must be a structurally valid candidate (span length equals
    // the original text length, replacement differs, span in range): an invalid
    // mutant must not appear in stable dogfood scope.
    for (c) |m| try expect(m.isValidCandidate(src.len));
}

test "phase 2 semantic dogfood: repeated runs are deterministic (same ids, same order)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a);

    var parsed1 = try ast_backend.parse(std.testing.allocator, fixture_path, src);
    defer parsed1.deinit();
    const run1 = try collectPhase2(a, parsed1);

    // Re-parse from scratch and re-collect (a fresh "dogfood run").
    var parsed2 = try ast_backend.parse(std.testing.allocator, fixture_path, src);
    defer parsed2.deinit();
    const run2 = try collectPhase2(a, parsed2);

    try expectEqual(run1.len, run2.len);
    for (run1, run2) |m1, m2| {
        try expectEqualStrings(m1.id, m2.id);
        try expectEqualStrings(m1.operator, m2.operator);
        try expectEqualStrings(m1.original, m2.original);
        try expectEqualStrings(m1.replacement, m2.replacement);
        try expectEqual(m1.span.byte_start, m2.span.byte_start);
    }
}
