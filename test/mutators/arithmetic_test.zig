const std = @import("std");
const zentinel = @import("zentinel");
const arithmetic = zentinel.mutators.arithmetic;
const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// Read at runtime relative to the project root (cwd during tests); @embedFile
// cannot reach a sibling fixtures directory from this test module's path.
fn readOps(a: std.mem.Allocator) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/fixtures/mutators/arithmetic/ops.zig", a, std.Io.Limit.limited(1 << 20));
}

fn collectArithmetic(a: std.mem.Allocator, parsed: ast_backend.Parsed) ![]mutant.Mutant {
    const test_ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try arithmetic.collect(&collector, parsed, "ops.zig", test_ranges);
    return collector.finish();
}

test "arithmetic operators emit + - * / swap candidates in canonical order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ops_src = try readOps(a);
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", ops_src);
    defer parsed.deinit();
    const c = try collectArithmetic(a, parsed);

    try expectEqual(@as(usize, 4), c.len);

    // Sorted by byte offset, the operators appear as + - * /.
    try expectEqualStrings("arithmetic_add_sub", c[0].operator);
    try expectEqualStrings("+", c[0].original);
    try expectEqualStrings("-", c[0].replacement);
    try expectEqual(mutant.ExpectedCompile.may_fail, c[0].expected_compile);

    try expectEqualStrings("arithmetic_add_sub", c[1].operator);
    try expectEqualStrings("-", c[1].original);
    try expectEqualStrings("+", c[1].replacement);

    try expectEqualStrings("arithmetic_mul_div", c[2].operator);
    try expectEqualStrings("*", c[2].original);
    try expectEqualStrings("/", c[2].replacement);

    try expectEqualStrings("arithmetic_mul_div", c[3].operator);
    try expectEqualStrings("/", c[3].original);
    try expectEqualStrings("*", c[3].replacement);

    // Canonical byte ordering and populated metadata.
    try expect(c[0].span.byte_start < c[1].span.byte_start);
    try expect(c[1].span.byte_start < c[2].span.byte_start);
    try expect(c[2].span.byte_start < c[3].span.byte_start);
    try expect(std.mem.startsWith(u8, c[0].id, "m_"));
    try expect(c[0].span.line_start >= 1 and c[0].span.column_start >= 1);
    try expect(c[0].backend == .ast);
    try expect(c[0].backend_stability == .stable);
}

test "unary minus is not mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "neg.zig",
        \\pub fn f(a: i32) i32 {
        \\    return -a;
        \\}
    );
    defer parsed.deinit();
    const c = try collectArithmetic(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "arithmetic operators inside test bodies are excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "mixed.zig",
        \\pub fn f(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\test "t" {
        \\    const x = 1 + 1;
        \\    _ = x;
        \\}
    );
    defer parsed.deinit();
    const c = try collectArithmetic(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("+", c[0].original);
}
