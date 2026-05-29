const std = @import("std");
const zentinel = @import("zentinel");
const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const mixed_src: []const u8 = @embedFile("fixtures/same_file_tests/mixed.zig");

fn cand(byte_start: u64, byte_end: u64) mutant.Mutant {
    return .{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = "arithmetic_add_sub",
        .operator_stability = .stable,
        .file = "mixed.zig",
        .span = .{ .byte_start = byte_start, .byte_end = byte_end, .line_start = 1, .column_start = 1, .line_end = 1, .column_end = 1 },
        .original = "+",
        .replacement = "-",
        .expected_compile = .compiles,
    };
}

test "test declaration ranges classify production vs test-body offsets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "mixed.zig", mixed_src);
    defer parsed.deinit();
    try expect(parsed.ok());

    const ranges = try ast_backend.testDeclRanges(parsed, a);
    try expectEqual(@as(usize, 1), ranges.len);

    const prod_plus: u32 = @intCast(std.mem.indexOf(u8, mixed_src, "a + b").? + 2);
    const test_plus: u32 = @intCast(std.mem.indexOf(u8, mixed_src, "1 + 0").? + 2);
    try expect(!ast_backend.inTestBody(ranges, prod_plus));
    try expect(ast_backend.inTestBody(ranges, test_plus));
}

test "production candidates remain while test-body candidates are excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "mixed.zig", mixed_src);
    defer parsed.deinit();
    const ranges = try ast_backend.testDeclRanges(parsed, a);

    const prod_plus: u64 = @intCast(std.mem.indexOf(u8, mixed_src, "a + b").? + 2);
    const test_plus: u64 = @intCast(std.mem.indexOf(u8, mixed_src, "1 + 0").? + 2);

    const candidates = [_]mutant.Mutant{
        cand(prod_plus, prod_plus + 1),
        cand(test_plus, test_plus + 1),
    };
    const kept = try ast_backend.excludeTestBodyCandidates(a, &candidates, ranges);
    try expectEqual(@as(usize, 1), kept.len);
    try expectEqual(prod_plus, kept[0].span.byte_start);
}
