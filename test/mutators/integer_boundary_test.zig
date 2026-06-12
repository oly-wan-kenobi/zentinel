const std = @import("std");
const zentinel = @import("zentinel");
const integer_boundary = zentinel.mutators.integer_boundary;
const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn collect(a: std.mem.Allocator, parsed: ast_backend.Parsed) ![]mutant.Mutant {
    const test_ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try integer_boundary.collect(&collector, parsed, "ops.zig", test_ranges);
    return collector.finish();
}

test "integer literals in branch and length checks get paired +1/-1 candidates in deterministic order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/integer_boundary/ops.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", src);
    defer parsed.deinit();
    const c = try collect(a, parsed);

    // `x < 10` and `s.len == 3`: two literals, two replacements each.
    try expectEqual(@as(usize, 4), c.len);
    for (c) |m| {
        try expectEqualStrings("integer_literal_boundary", m.operator);
        try expectEqual(mutant.ExpectedCompile.may_fail, m.expected_compile);
        try expect(m.backend == .ast and m.backend_stability == .stable);
    }

    // Canonical order: by byte (10 before 3), then by replacement string.
    try expectEqualStrings("10", c[0].original);
    try expectEqualStrings("11", c[0].replacement);
    try expectEqualStrings("10", c[1].original);
    try expectEqualStrings("9", c[1].replacement);
    try expectEqualStrings("3", c[2].original);
    try expectEqualStrings("2", c[2].replacement);
    try expectEqualStrings("3", c[3].original);
    try expectEqualStrings("4", c[3].replacement);

    try expect(c[0].span.byte_start < c[2].span.byte_start);
    try expect(std.mem.startsWith(u8, c[0].id, "m_"));
}

test "protected literals (declarations, enum tags, lengths, alignments) are not mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/integer_boundary/protected.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "protected.zig", src);
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "zero and one boundary literals are mutated (including negative -1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "z.zig",
        \\pub fn f(x: i32) bool {
        \\    return x > 0;
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 2), c.len);
    // 0 -> +1 = "1", -1 = "-1"; canonical order sorts "-1" before "1".
    try expectEqualStrings("0", c[0].original);
    try expectEqualStrings("-1", c[0].replacement);
    try expectEqualStrings("0", c[1].original);
    try expectEqualStrings("1", c[1].replacement);
}

test "non-decimal literals (hex) are left alone for now" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "h.zig",
        \\pub fn f(x: u32) bool {
        \\    return x < 0x10;
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "literals outside comparisons (assignments) are not mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "a.zig",
        \\pub fn f() i32 {
        \\    const limit = 100;
        \\    return limit;
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "integer literals inside test bodies are excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "t.zig",
        \\pub fn f(x: i32) bool {
        \\    return x < 5;
        \\}
        \\test "t" {
        \\    const y: i32 = 2;
        \\    try @import("std").testing.expect(y < 9);
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    // Only the production `x < 5` literal; the `9` in the test-body comparison
    // is excluded.
    try expectEqual(@as(usize, 2), c.len);
    try expectEqualStrings("5", c[0].original);
}

test "an i128-max comparison literal skips the overflowing +1 boundary instead of panicking" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // i128 max = 2^127 - 1 = 170141183460469231731687303715884105727. Pre-fix the
    // mutator computed `value + 1` in i128 with no bounds check, so this legal
    // source literal aborted the WHOLE candidate-generation pass with an
    // unrecoverable `panic: integer overflow`. The mutator must instead drop just
    // the unrepresentable +1 boundary and still emit the -1 boundary.
    var parsed = try ast_backend.parse(std.testing.allocator, "max.zig",
        \\pub fn f(x: i128) bool {
        \\    return x == 170141183460469231731687303715884105727;
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    // Exactly one candidate survives: the -1 boundary (max - 1). The +1 boundary
    // is unrepresentable in i128 and is skipped, not crashed on.
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("170141183460469231731687303715884105727", c[0].original);
    try expectEqualStrings("170141183460469231731687303715884105726", c[0].replacement);
    try expectEqual(mutant.ExpectedCompile.may_fail, c[0].expected_compile);
}
