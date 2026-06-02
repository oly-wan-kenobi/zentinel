const std = @import("std");
const zentinel = @import("zentinel");
const logical = zentinel.mutators.logical;
const boolean = zentinel.mutators.boolean;
const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readOps(a: std.mem.Allocator) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/fixtures/mutators/logical_boolean/ops.zig", a, std.Io.Limit.limited(1 << 20));
}


test "logical operators emit and<->or swaps in canonical order with exact spans" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ops_src = try readOps(a);
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", ops_src);
    defer parsed.deinit();
    const ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try logical.collect(&collector, parsed, "ops.zig", ranges);
    const c = try collector.finish();

    try expectEqual(@as(usize, 3), c.len);
    try expectEqualStrings("logical_and_or", c[0].operator);
    try expectEqualStrings("and", c[0].original);
    try expectEqualStrings("or", c[0].replacement);
    // Short-circuit operator span is exactly the keyword.
    try expectEqual(@as(u64, 3), c[0].span.byte_end - c[0].span.byte_start);
    try expectEqualStrings("or", c[1].original);
    try expectEqualStrings("and", c[1].replacement);
    try expectEqualStrings("or", c[2].original);
    try expectEqual(mutant.ExpectedCompile.compiles, c[0].expected_compile);
    try expect(c[0].equivalent_risks.len > 0);
}

test "boolean literals emit true<->false swaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ops_src = try readOps(a);
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", ops_src);
    defer parsed.deinit();
    const ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try boolean.collect(&collector, parsed, "ops.zig", ranges);
    const c = try collector.finish();

    try expectEqual(@as(usize, 2), c.len);
    try expectEqualStrings("boolean_literal", c[0].operator);
    try expectEqualStrings("true", c[0].original);
    try expectEqualStrings("false", c[0].replacement);
    try expectEqualStrings("false", c[1].original);
    try expectEqualStrings("true", c[1].replacement);
    try expectEqual(mutant.ExpectedCompile.compiles, c[0].expected_compile);
}

test "boolean_literal skips enum field declarations named true/false (L23)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `enum { true, false }` declares its members as tuple-like container fields
    // whose type_expr is a `true`/`false` identifier. Mutating a field NAME would
    // emit `enum { false, false }` -- a guaranteed `duplicate enum member name`
    // compile_error and a spec-Forbidden (field names) context. Only the genuine
    // boolean VALUE `return true` in b() may be mutated, so exactly ONE candidate
    // is emitted, not three (L23).
    var parsed = try ast_backend.parse(std.testing.allocator, "e.zig",
        \\const E = enum { true, false };
        \\pub fn use() E {
        \\    return E.true;
        \\}
        \\pub fn b() bool {
        \\    return true;
        \\}
    );
    defer parsed.deinit();
    const ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try boolean.collect(&collector, parsed, "e.zig", ranges);
    const c = try collector.finish();

    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("boolean_literal", c[0].operator);
    try expectEqualStrings("true", c[0].original);
    try expectEqualStrings("false", c[0].replacement);
    // The sole candidate is the value in b()'s body (line 6), never an enum field
    // name (line 1).
    try expectEqual(@as(u32, 6), c[0].span.line_start);
}

test "candidate order is stable with mixed logical and boolean candidates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ops_src = try readOps(a);
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", ops_src);
    defer parsed.deinit();
    const ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try logical.collect(&collector, parsed, "ops.zig", ranges);
    try boolean.collect(&collector, parsed, "ops.zig", ranges);
    const c = try collector.finish();

    // Byte order interleaves: `and`, `true`, `or`, `false`, `or`.
    try expectEqual(@as(usize, 5), c.len);
    try expectEqualStrings("logical_and_or", c[0].operator);
    try expectEqualStrings("boolean_literal", c[1].operator);
    try expectEqualStrings("logical_and_or", c[2].operator);
    try expectEqualStrings("boolean_literal", c[3].operator);
    try expectEqualStrings("logical_and_or", c[4].operator);
    var i: usize = 1;
    while (i < c.len) : (i += 1) try expect(c[i - 1].span.byte_start < c[i].span.byte_start);
}

test "boolean literals in comments and strings are not mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "textonly.zig",
        \\pub fn f() []const u8 {
        \\    // true and false
        \\    return "true or false";
        \\}
    );
    defer parsed.deinit();
    const ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try boolean.collect(&collector, parsed, "ops.zig", ranges);
    const c = try collector.finish();
    try expectEqual(@as(usize, 0), c.len);
}
