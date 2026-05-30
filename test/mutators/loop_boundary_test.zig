const std = @import("std");
const zentinel = @import("zentinel");
const loop_boundary = zentinel.mutators.loop_boundary;
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
    try loop_boundary.collect(&collector, parsed, "ops.zig", test_ranges);
    return collector.finish();
}

test "while comparison boundary swap and range-end +1/-1 in deterministic order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/loop_boundary/ops.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", src);
    defer parsed.deinit();
    const c = try collect(a, parsed);

    // `while (i < n)` boundary swap, then `for (0..10)` range end +1/-1.
    try expectEqual(@as(usize, 3), c.len);
    for (c) |m| try expectEqualStrings("loop_boundary", m.operator);

    // Boundary swap of the loop condition compiles; it sorts first (earlier byte).
    try expectEqualStrings("<", c[0].original);
    try expectEqualStrings("<=", c[0].replacement);
    try expectEqual(mutant.ExpectedCompile.compiles, c[0].expected_compile);

    // Range end +1/-1 can overflow the loop type -> may_fail.
    try expectEqualStrings("10", c[1].original);
    try expectEqualStrings("11", c[1].replacement);
    try expectEqual(mutant.ExpectedCompile.may_fail, c[1].expected_compile);
    try expectEqualStrings("10", c[2].original);
    try expectEqualStrings("9", c[2].replacement);

    try expect(c[0].span.byte_start < c[1].span.byte_start);
    try expect(std.mem.startsWith(u8, c[0].id, "m_"));
}

test "an infinite loop (while true) is skipped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/loop_boundary/infinite.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "infinite.zig", src);
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "a while with a continue expression has its boundary mutated (and only that)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "wc.zig",
        \\pub fn f(n: usize) usize {
        \\    var i: usize = 0;
        \\    while (i <= n) : (i += 1) {}
        \\    return i;
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("loop_boundary", c[0].operator);
    try expectEqualStrings("<=", c[0].original);
    try expectEqualStrings("<", c[0].replacement);
    try expectEqual(mutant.ExpectedCompile.compiles, c[0].expected_compile);
}

test "a non-literal range end is left alone (syntactically unsafe to +/-1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "nr.zig",
        \\pub fn f(n: usize) usize {
        \\    var total: usize = 0;
        \\    for (0..n) |x| {
        \\        total += x;
        \\    }
        \\    return total;
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "loop boundaries inside test bodies are excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "t.zig",
        \\pub fn f(n: usize) bool {
        \\    return n < 4;
        \\}
        \\test "t" {
        \\    var i: usize = 0;
        \\    while (i < 3) {
        \\        i += 1;
        \\    }
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    // The production `n < 4` is not a loop condition (no while/for), so 0 from it;
    // the test-body `while (i < 3)` boundary is excluded.
    try expectEqual(@as(usize, 0), c.len);
}
