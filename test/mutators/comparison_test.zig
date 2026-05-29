const std = @import("std");
const zentinel = @import("zentinel");
const comparison = zentinel.mutators.comparison;
const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readOps(a: std.mem.Allocator) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/fixtures/mutators/comparison/ops.zig", a, std.Io.Limit.limited(1 << 20));
}

fn collectComparison(a: std.mem.Allocator, parsed: ast_backend.Parsed) ![]mutant.Mutant {
    const test_ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try comparison.collect(&collector, parsed, "ops.zig", test_ranges);
    return collector.finish();
}

test "equality and boundary operators emit the documented swaps in canonical order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ops_src = try readOps(a);
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", ops_src);
    defer parsed.deinit();
    const c = try collectComparison(a, parsed);

    try expectEqual(@as(usize, 6), c.len);

    const expected = [_]struct { op: []const u8, orig: []const u8, repl: []const u8 }{
        .{ .op = "equality_swap", .orig = "==", .repl = "!=" },
        .{ .op = "equality_swap", .orig = "!=", .repl = "==" },
        .{ .op = "comparison_boundary", .orig = "<", .repl = "<=" },
        .{ .op = "comparison_boundary", .orig = "<=", .repl = "<" },
        .{ .op = "comparison_boundary", .orig = ">", .repl = ">=" },
        .{ .op = "comparison_boundary", .orig = ">=", .repl = ">" },
    };
    for (expected, 0..) |e, i| {
        try expectEqualStrings(e.op, c[i].operator);
        try expectEqualStrings(e.orig, c[i].original);
        try expectEqualStrings(e.repl, c[i].replacement);
        try expectEqual(mutant.ExpectedCompile.compiles, c[i].expected_compile);
        if (i > 0) try expect(c[i - 1].span.byte_start < c[i].span.byte_start);
    }

    // Equivalent-risk hints from MUTATOR_SPEC are carried on the model.
    try expect(c[0].equivalent_risks.len > 0);
    try expect(c[2].equivalent_risks.len > 0);
}

test "null comparisons are left to optional_null_check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "nullcmp.zig",
        \\pub fn f(x: ?i32) bool {
        \\    return x == null or x != null;
        \\}
    );
    defer parsed.deinit();
    const c = try collectComparison(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "operators inside comments and strings are not mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "textonly.zig",
        \\pub fn f() []const u8 {
        \\    // a <= b and c == d
        \\    return "x >= y != z";
        \\}
    );
    defer parsed.deinit();
    const c = try collectComparison(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}
