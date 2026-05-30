const std = @import("std");
const zentinel = @import("zentinel");
const error_path = zentinel.mutators.error_path;
const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn collectErrorPath(a: std.mem.Allocator, parsed: ast_backend.Parsed) ![]mutant.Mutant {
    const test_ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try error_path.collect(&collector, parsed, "ops.zig", test_ranges);
    return collector.finish();
}

test "catch handler -> catch unreachable in canonical order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/error_path/ops.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", src);
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);

    // parseOr (catch 0) and handled (catch -1); alreadyUnreachable is skipped.
    try expectEqual(@as(usize, 2), c.len);

    try expectEqualStrings("error_catch_unreachable", c[0].operator);
    try expectEqualStrings("0", c[0].original);
    try expectEqualStrings("unreachable", c[0].replacement);
    try expectEqual(mutant.ExpectedCompile.may_fail, c[0].expected_compile);

    try expectEqualStrings("error_catch_unreachable", c[1].operator);
    try expectEqualStrings("-1", c[1].original);
    try expectEqualStrings("unreachable", c[1].replacement);

    try expect(c[0].span.byte_start < c[1].span.byte_start);
    try expect(std.mem.startsWith(u8, c[0].id, "m_"));
    try expect(c[0].backend == .ast and c[0].backend_stability == .stable);
    try expect(c[0].equivalent_risks.len > 0);
}

test "an existing catch unreachable is not mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "cu.zig",
        \\pub fn f(e: anyerror!i32) i32 {
        \\    return e catch unreachable;
        \\}
    );
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "a catch with an |err| payload replaces only the handler expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "p.zig",
        \\pub fn f(e: anyerror!i32) i32 {
        \\    return e catch |err| handle(err);
        \\}
        \\fn handle(_: anyerror) i32 {
        \\    return -1;
        \\}
    );
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("error_catch_unreachable", c[0].operator);
    // The span is the handler expression only, not the `|err|` capture.
    try expectEqualStrings("handle(err)", c[0].original);
    try expectEqualStrings("unreachable", c[0].replacement);
}

test "survivor fixture: never-exercised error path yields a catch candidate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/error_path/survivor.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "survivor.zig", src);
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("error_catch_unreachable", c[0].operator);
    try expectEqualStrings("0", c[0].original);
}

test "killed fixture: production catch candidate emitted, test body excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/error_path/killed.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "killed.zig", src);
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("0", c[0].original);
}
