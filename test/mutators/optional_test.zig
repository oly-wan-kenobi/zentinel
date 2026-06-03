const std = @import("std");
const zentinel = @import("zentinel");
const optional = zentinel.mutators.optional;
const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn collectOptional(a: std.mem.Allocator, parsed: ast_backend.Parsed) ![]mutant.Mutant {
    const test_ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try optional.collect(&collector, parsed, "ops.zig", test_ranges);
    return collector.finish();
}

test "optional mutators emit orelse->unreachable and null-check swaps in canonical order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/optional/ops.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", src);
    defer parsed.deinit();
    const c = try collectOptional(a, parsed);

    try expectEqual(@as(usize, 4), c.len);

    // Sorted by byte offset: orelse fallback, then x==null, x!=null, null==x.
    try expectEqualStrings("optional_orelse_unreachable", c[0].operator);
    try expectEqualStrings("0", c[0].original);
    try expectEqualStrings("unreachable", c[0].replacement);
    try expectEqual(mutant.ExpectedCompile.may_fail, c[0].expected_compile);

    try expectEqualStrings("optional_null_check", c[1].operator);
    try expectEqualStrings("==", c[1].original);
    try expectEqualStrings("!=", c[1].replacement);
    try expectEqual(mutant.ExpectedCompile.compiles, c[1].expected_compile);

    try expectEqualStrings("optional_null_check", c[2].operator);
    try expectEqualStrings("!=", c[2].original);
    try expectEqualStrings("==", c[2].replacement);

    try expectEqualStrings("optional_null_check", c[3].operator);
    try expectEqualStrings("==", c[3].original); // null == x
    try expectEqualStrings("!=", c[3].replacement);

    try expect(c[0].span.byte_start < c[1].span.byte_start);
    try expect(c[1].span.byte_start < c[2].span.byte_start);
    try expect(c[2].span.byte_start < c[3].span.byte_start);
    try expect(std.mem.startsWith(u8, c[0].id, "m_"));
    try expect(c[0].backend == .ast and c[0].backend_stability == .stable);
}

test "null != x (null literal on the left) is recognized as optional_null_check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "nf.zig",
        \\pub fn f(x: ?i32) bool {
        \\    return null != x;
        \\}
    );
    defer parsed.deinit();
    const c = try collectOptional(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("optional_null_check", c[0].operator);
    try expectEqualStrings("!=", c[0].original);
    try expectEqualStrings("==", c[0].replacement);
}

test "an existing orelse unreachable is not re-mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "ou.zig",
        \\pub fn f(x: ?i32) i32 {
        \\    return x orelse unreachable;
        \\}
    );
    defer parsed.deinit();
    const c = try collectOptional(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "non-null equality is left to the comparison mutator (no optional_null_check)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "eq.zig",
        \\pub fn f(x: i32, y: i32) bool {
        \\    return x == y;
        \\}
    );
    defer parsed.deinit();
    const c = try collectOptional(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "optional survivor fixture: orelse fallback yields a candidate that survives without a null-path test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/optional/survivor.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "survivor.zig", src);
    defer parsed.deinit();
    const c = try collectOptional(a, parsed);

    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("optional_orelse_unreachable", c[0].operator);
    try expectEqualStrings("42", c[0].original);
    try expectEqualStrings("unreachable", c[0].replacement);
}

test "optional operators inside test bodies are excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "mixed.zig",
        \\pub fn f(x: ?i32) i32 {
        \\    return x orelse 0;
        \\}
        \\test "t" {
        \\    const y: ?i32 = null;
        \\    _ = y orelse 1;
        \\}
    );
    defer parsed.deinit();
    const c = try collectOptional(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("optional_orelse_unreachable", c[0].operator);
    try expectEqualStrings("0", c[0].original);
}

test "a parenthesized orelse unreachable is not re-mutated (L6)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `orelse (unreachable)` is already semantically `orelse unreachable`; mutating
    // it only strips the redundant parens -- a pure no-op equivalent survivor that
    // the exact-string guard missed (L6).
    var parsed = try ast_backend.parse(std.testing.allocator, "o.zig",
        \\pub fn f(x: ?i32) i32 {
        \\    return x orelse (unreachable);
        \\}
    );
    defer parsed.deinit();
    const c = try collectOptional(a, parsed);
    for (c) |m| try expect(!std.mem.eql(u8, m.operator, "optional_orelse_unreachable"));
}
