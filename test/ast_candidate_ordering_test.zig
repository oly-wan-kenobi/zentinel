const std = @import("std");
const zentinel = @import("zentinel");
const mutant = zentinel.mutant;
const ast_backend = zentinel.ast_backend;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Small candidate builder used only by tests until real recognizers exist.
fn mk(file: []const u8, byte_start: u64, byte_end: u64, operator: []const u8, original: []const u8, replacement: []const u8) mutant.Mutant {
    return .{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = operator,
        .operator_stability = .stable,
        .file = file,
        .span = .{ .byte_start = byte_start, .byte_end = byte_end, .line_start = 1, .column_start = 1, .line_end = 1, .column_end = 1 },
        .original = original,
        .replacement = replacement,
        .expected_compile = .compiles,
    };
}

test "candidates sort canonically by file, span, operator, replacement, backend" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var collector = ast_backend.Collector.init(a);
    try collector.add(mk("src/b.zig", 10, 12, "comparison_boundary", "<", "<="));
    try collector.add(mk("src/a.zig", 10, 12, "comparison_boundary", "<", "<="));
    try collector.add(mk("src/a.zig", 5, 7, "comparison_boundary", "<", "<="));
    try collector.add(mk("src/a.zig", 10, 12, "arithmetic_add_sub", "+", "-"));

    const items = try collector.finish();
    try expectEqual(@as(usize, 4), items.len);
    // src/a.zig before src/b.zig; within a.zig byte 5 before 10; at byte 10,
    // operator arithmetic_add_sub before comparison_boundary.
    try expectEqualStrings("src/a.zig", items[0].file);
    try expectEqual(@as(u64, 5), items[0].span.byte_start);
    try expectEqualStrings("arithmetic_add_sub", items[1].operator);
    try expectEqualStrings("comparison_boundary", items[2].operator);
    try expectEqualStrings("src/b.zig", items[3].file);

    // Durable ids are assigned during collection.
    for (items) |m| try expect(std.mem.startsWith(u8, m.id, "m_"));
}

test "identical candidates are deduplicated by durable identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var collector = ast_backend.Collector.init(a);
    const dup = mk("src/a.zig", 10, 12, "comparison_boundary", ">=", ">");
    try collector.add(dup);
    try collector.add(dup); // exact duplicate identity -> removed
    try collector.add(mk("src/a.zig", 10, 12, "comparison_boundary", ">=", "<")); // distinct replacement

    const items = try collector.finish();
    try expectEqual(@as(usize, 2), items.len);
    try expect(!std.mem.eql(u8, items[0].id, items[1].id));
}

test "candidate order is stable across repeated collection in different insertion orders" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const set = [_]mutant.Mutant{
        mk("src/z.zig", 1, 2, "comparison_boundary", "<", "<="),
        mk("src/a.zig", 30, 31, "arithmetic_add_sub", "+", "-"),
        mk("src/a.zig", 10, 11, "comparison_boundary", ">", ">="),
    };

    var forward = ast_backend.Collector.init(a);
    for (set) |c| try forward.add(c);
    const r1 = try forward.finish();

    var reverse = ast_backend.Collector.init(a);
    var i: usize = set.len;
    while (i > 0) {
        i -= 1;
        try reverse.add(set[i]);
    }
    const r2 = try reverse.finish();

    try expectEqual(r1.len, r2.len);
    for (r1, r2) |x, y| try expectEqualStrings(x.id, y.id);
}
