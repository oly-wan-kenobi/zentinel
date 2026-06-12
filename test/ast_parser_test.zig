const std = @import("std");
const zentinel = @import("zentinel");
const source_map = zentinel.source_map;
const ast_backend = zentinel.ast_backend;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const valid_src = @embedFile("fixtures/ast_parser/valid.zig");
// Stored as `.zig.txt` so `zig fmt` does not try to parse the deliberately
// invalid source; it is embedded as bytes and parsed under a representative name.
const invalid_src = @embedFile("fixtures/ast_parser/invalid.zig.txt");

test "source map round-trips byte offsets to 1-based line/column" {
    const src = "fn a() void {}\nconst x = 1;\n";
    const at0 = source_map.locate(src, 0).?;
    try expectEqual(@as(u32, 1), at0.line);
    try expectEqual(@as(u32, 1), at0.column);

    // Index 15 is the first character of line 2 (after the first newline at 14).
    const at15 = source_map.locate(src, 15).?;
    try expectEqual(@as(u32, 2), at15.line);
    try expectEqual(@as(u32, 1), at15.column);

    // Byte -> position -> byte round-trips for every offset including EOF.
    var i: usize = 0;
    while (i <= src.len) : (i += 1) {
        const pos = source_map.locate(src, i).?;
        try expectEqual(i, source_map.byteOf(src, pos).?);
    }
}

test "source map rejects out-of-range offsets and positions (F-008 guardrail)" {
    const src = "abc";
    try expect(source_map.locate(src, 3) != null); // EOF position is valid
    try expect(source_map.locate(src, 4) == null); // beyond end
    try expect(source_map.byteOf(src, .{ .line = 1, .column = 0 }) == null); // column is 1-based
    try expect(source_map.byteOf(src, .{ .line = 5, .column = 1 }) == null); // line beyond source
    try expect(source_map.byteOf(src, .{ .line = 1, .column = 9 }) == null); // column beyond line
}

test "LineIndex.locate is byte-for-byte equivalent to locate over every offset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const samples = [_][]const u8{ valid_src, "", "\n", "no newline", "a\nbb\nccc\n", "\n\n\nx", "trailing\n", "\r\nwin\r\n" };
    for (samples) |src| {
        const li = try source_map.LineIndex.init(a, src);
        var i: usize = 0;
        while (i <= src.len) : (i += 1) {
            const want = source_map.locate(src, i).?;
            const got = li.locate(i).?;
            try expectEqual(want.line, got.line);
            try expectEqual(want.column, got.column);
        }
        // Out-of-range parity with the scalar locate.
        try expect(li.locate(src.len + 1) == null);
    }
}

test "parses valid Zig with no diagnostics and a non-empty node set" {
    var parsed = try ast_backend.parse(std.testing.allocator, "test/fixtures/ast_parser/valid.zig", valid_src);
    defer parsed.deinit();
    try expect(parsed.ok());
    try expectEqual(@as(usize, 0), parsed.diagnostics().len);
    try expect(parsed.nodeCount() > 0);
}

test "reports parse diagnostics with file and location on invalid Zig (F-007)" {
    var parsed = try ast_backend.parse(std.testing.allocator, "broken.zig", invalid_src);
    defer parsed.deinit();
    try expect(!parsed.ok());
    const diags = parsed.diagnostics();
    try expect(diags.len > 0);
    try expectEqualStrings("broken.zig", diags[0].file);
    try expect(diags[0].line >= 1);
    try expect(diags[0].column >= 1);
    try expect(diags[0].message.len > 0);
    try expect(diags[0].byte_offset <= invalid_src.len);
}

test "traversal order is deterministic for the same source" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var first = try ast_backend.parse(std.testing.allocator, "f.zig", valid_src);
    defer first.deinit();
    var second = try ast_backend.parse(std.testing.allocator, "f.zig", valid_src);
    defer second.deinit();

    const sig1 = try first.traversalSignature(a);
    const sig2 = try second.traversalSignature(a);
    try expectEqualStrings(sig1, sig2);
    try expect(sig1.len > 0);
}
