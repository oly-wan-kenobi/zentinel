const std = @import("std");
const zentinel = @import("zentinel");
const parser = zentinel.doctest.parser;
const block = zentinel.doctest.block;
const error_codes = zentinel.error_codes;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn parse(a: std.mem.Allocator, src: []const u8) !parser.Parsed {
    return parser.parse(a, "doc.md", src);
}

fn firstDoctest(p: parser.Parsed) ?block.Block {
    for (p.blocks) |b| {
        if (b.is_doctest) return b;
    }
    return null;
}

fn doctestCount(p: parser.Parsed) usize {
    var n: usize = 0;
    for (p.blocks) |b| {
        if (b.is_doctest) n += 1;
    }
    return n;
}

test "parses a supported `zig test` block with line numbers and raw content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src =
        "# Title\n" ++ // 1
        "\n" ++ // 2
        "Some prose.\n" ++ // 3
        "\n" ++ // 4
        "```zig test\n" ++ // 5 opening fence
        "const x = 1;\n" ++ // 6
        "```\n"; // 7 closing fence

    const p = try parse(a, src);
    try expectEqual(@as(usize, 0), p.diagnostics.len);
    try expectEqual(@as(usize, 1), doctestCount(p));

    const b = firstDoctest(p).?;
    try expectEqual(block.Language.zig, b.language);
    try expectEqual(block.Kind.unit_test, b.kind);
    try expect(b.is_doctest);
    try expectEqualStrings("zig test", b.info);
    try expectEqualStrings("const x = 1;\n", b.content);
    try expectEqual(@as(u32, 5), b.line_start);
    try expectEqual(@as(u32, 7), b.line_end);
    try expectEqual(@as(u8, 3), b.fence_len);
}

test "unsupported executable doctest tag emits ZNTL_DOCTEST_UNSUPPORTED_TAG" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "```zig frobnicate\nconst x = 1;\n```\n";
    const p = try parse(a, src);
    try expectEqual(@as(usize, 1), p.diagnostics.len);
    try expectEqualStrings(error_codes.doctest_unsupported_tag, p.diagnostics[0].code);
    try expectEqual(@as(u32, 1), p.diagnostics[0].line);
    try expectEqual(@as(usize, 0), doctestCount(p)); // not an executable doctest
}

test "ordinary non-doctest language blocks are documentation-only with no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "```python\nprint(1)\n```\n";
    const p = try parse(a, src);
    try expectEqual(@as(usize, 0), p.diagnostics.len);
    try expectEqual(@as(usize, 1), p.blocks.len);
    try expect(!p.blocks[0].is_doctest);
    try expectEqual(block.Language.other, p.blocks[0].language);
}

test "a quadruple-backtick block keeps a nested triple-backtick example as content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src =
        "````md\n" ++ // 1 four-backtick open
        "```zig test\n" ++ // 2 nested triple-backtick (content)
        "const x = 1;\n" ++ // 3
        "```\n" ++ // 4 nested close (content)
        "````\n"; // 5 four-backtick close

    const p = try parse(a, src);
    // The nested zig test is content, not a separate block.
    try expectEqual(@as(usize, 0), doctestCount(p));
    try expectEqual(@as(usize, 1), p.blocks.len);
    const b = p.blocks[0];
    try expectEqual(@as(u8, 4), b.fence_len);
    try expectEqual(@as(u32, 1), b.line_start);
    try expectEqual(@as(u32, 5), b.line_end);
    try expect(std.mem.indexOf(u8, b.content, "```zig test") != null);
    try expect(std.mem.indexOf(u8, b.content, "const x = 1;") != null);
}

test "five-backtick fences are documentation-only even with a doctest tag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "`````zig test\nconst x = 1;\n`````\n";
    const p = try parse(a, src);
    try expectEqual(@as(usize, 0), p.diagnostics.len);
    try expectEqual(@as(usize, 0), doctestCount(p));
    try expectEqual(@as(usize, 1), p.blocks.len);
    try expect(!p.blocks[0].is_doctest);
    try expectEqual(@as(u8, 5), p.blocks[0].fence_len);
}

test "an unclosed doctest fence emits ZNTL_DOCTEST_INVALID_BLOCK" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = "```zig test\nconst x = 1;\n"; // never closed
    const p = try parse(a, src);
    try expectEqual(@as(usize, 1), p.diagnostics.len);
    try expectEqualStrings(error_codes.doctest_invalid_block, p.diagnostics[0].code);
}

test "info-string variants classify language, kind, and match mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src =
        "```bash cli case:help\nzentinel --help\n```\n" ++
        "```json expected subset\n{}\n```\n" ++
        "```text output contains\nhi\n```\n" ++
        "```toml config\n[project]\n```\n" ++
        "```zig before\nreturn a + b;\n```\n" ++
        "```zig after\nreturn a - b;\n```\n";
    const p = try parse(a, src);
    try expectEqual(@as(usize, 0), p.diagnostics.len);
    try expectEqual(@as(usize, 6), doctestCount(p));

    try expectEqual(block.Language.bash, p.blocks[0].language);
    try expectEqual(block.Kind.cli, p.blocks[0].kind);
    try expectEqualStrings("help", p.blocks[0].case_label.?);
    try expectEqual(block.Language.json, p.blocks[1].language);
    try expectEqual(block.Kind.expected, p.blocks[1].kind);
    try expectEqual(block.MatchMode.subset, p.blocks[1].match_mode);
    try expectEqual(block.MatchMode.contains, p.blocks[2].match_mode);
    try expectEqual(block.Language.toml, p.blocks[3].language);
    try expectEqual(block.Kind.config, p.blocks[3].kind);
    try expectEqual(block.Kind.before, p.blocks[4].kind);
    try expectEqual(block.Kind.after, p.blocks[5].kind);
}

test "parses a fixture markdown file into the expected doctest blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const path = "test/fixtures/doctest/parser/sample.md";
    const src = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
    const p = try parser.parse(a, path, src);

    try expectEqual(@as(usize, 0), p.diagnostics.len);
    try expectEqual(@as(usize, 2), doctestCount(p)); // zig test + bash cli; python is doc-only
    const dt = firstDoctest(p).?;
    try expectEqual(block.Language.zig, dt.language);
    try expectEqual(block.Kind.unit_test, dt.kind);
    try expectEqualStrings(path, dt.file);
}

test "parsing is deterministic and prose-invariant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bare = "```zig test\nconst x = 1;\n```\n";
    const surrounded = "lead prose\n\n## heading\n\n" ++ bare ++ "\ntrailing prose\n";

    const r1 = try parse(a, bare);
    const r2 = try parse(a, bare);
    try expectEqual(r1.blocks.len, r2.blocks.len);
    for (r1.blocks, r2.blocks) |x, y| {
        try expectEqualStrings(x.content, y.content);
        try expectEqual(x.line_start, y.line_start);
        try expectEqualStrings(x.info, y.info);
    }

    // Prose around the fence does not change extracted content.
    const rs = try parse(a, surrounded);
    const db = firstDoctest(rs).?;
    try expectEqualStrings("const x = 1;\n", db.content);
}
