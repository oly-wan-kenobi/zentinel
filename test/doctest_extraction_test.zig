const std = @import("std");
const zentinel = @import("zentinel");
const extractor = zentinel.doctest.extractor;
const case = zentinel.doctest.case;
const block = zentinel.doctest.block;
const error_codes = zentinel.error_codes;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn extractFile(a: std.mem.Allocator, path: []const u8) !extractor.Extracted {
    const src = try readFixture(a, path);
    return extractor.extractSource(a, path, src);
}

fn findCase(ex: extractor.Extracted, kind: case.CaseKind) ?case.Case {
    for (ex.cases) |c| {
        if (c.kind == kind) return c;
    }
    return null;
}

const cases_fixture = "test/fixtures/doctest/extraction/cases.md";

test "groups bash cli with following text output into one cli case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ex = try extractFile(a, cases_fixture);
    const c = findCase(ex, .cli).?;
    try expectEqual(case.CaseKind.cli, c.kind);
    // Producer + its expectation block group into one case.
    try expectEqual(@as(usize, 2), c.block_refs.len);
    // The anchor source_ref points at the producer (cli) line, never the
    // expectation block; line numbers are display-only and live in refs.
    try expectEqual(c.anchor_line, c.line_start);
    try expect(std.mem.startsWith(u8, c.source_ref, cases_fixture ++ ":"));
    try expectEqualStrings(c.block_refs[0], c.source_ref);
}

test "zig before + zig after group into a mutation case; standalone toml config is its own case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ex = try extractFile(a, cases_fixture);

    const m = findCase(ex, .mutation).?;
    try expectEqual(@as(usize, 2), m.block_refs.len); // before + after

    const cfg = findCase(ex, .config).?;
    try expectEqual(@as(usize, 1), cfg.block_refs.len);

    const zt = findCase(ex, .zig_test).?;
    try expectEqual(@as(usize, 1), zt.block_refs.len);

    // The whole fixture is valid: four grouped cases, no diagnostics.
    try expectEqual(@as(usize, 4), ex.cases.len);
    try expectEqual(@as(usize, 0), ex.diagnostics.len);
}

test "json expected without a producer is an invalid grouping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ex = try extractFile(a, "test/fixtures/doctest/extraction/orphan.md");
    try expectEqual(@as(usize, 0), ex.cases.len);
    try expectEqual(@as(usize, 1), ex.diagnostics.len);
    try expectEqualStrings(error_codes.doctest_invalid_block, ex.diagnostics[0].code);
}

test "deterministic case id snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ex = try extractFile(a, cases_fixture);
    const c = findCase(ex, .cli).?;
    // Durable id shape: `dt_` + 26 lowercase Crockford base32 chars.
    try expectEqual(@as(usize, 29), c.id.len);
    try expect(std.mem.startsWith(u8, c.id, "dt_"));
    // Pinned snapshot of the durable id (self-blessed; any change to the id
    // algorithm or grouped content must change this).
    try expectEqualStrings("dt_hszypy3emq5e1qngetceqbvgj4", c.id);
}

test "case inventory snapshot records id, source_ref, block_refs, and location fields separately" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ex = try extractFile(a, cases_fixture);
    const got = try extractor.renderInventory(a, ex);
    const want = try readFixture(a, "test/fixtures/doctest/extraction/cases.inventory.json");
    try expectEqualStrings(want, got);
}

test "duplicate unlabeled identical cases are rejected as ambiguous, not occurrence-numbered" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ex = try extractFile(a, "test/fixtures/doctest/extraction/duplicate.md");
    // Both identical unlabeled cases are rejected; none is emitted with an
    // occurrence-based id.
    try expectEqual(@as(usize, 0), ex.cases.len);
    try expect(ex.diagnostics.len >= 1);
    for (ex.diagnostics) |d| {
        try expectEqualStrings(error_codes.doctest_invalid_block, d.code);
    }
}

test "property: extraction is deterministic across repeated runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, cases_fixture);
    const r1 = try extractor.extractSource(a, cases_fixture, src);
    const r2 = try extractor.extractSource(a, cases_fixture, src);
    try expectEqual(r1.cases.len, r2.cases.len);
    for (r1.cases, r2.cases) |x, y| {
        try expectEqualStrings(x.id, y.id);
        try expectEqual(x.kind, y.kind);
        try expectEqualStrings(x.source_ref, y.source_ref);
        try expectEqual(x.line_start, y.line_start);
        try expectEqual(x.line_end, y.line_end);
    }
}

test "property: case id changes with grouped content and labels, stable under outside prose" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const base = "```zig test\ntest \"a\" { try @import(\"std\").testing.expect(true); }\n```\n";
    const e_base = try extractor.extractSource(a, "doc.md", base);
    const id_base = e_base.cases[0].id;

    // Unrelated prose outside the case does not change the durable id.
    const with_prose = "# Heading\n\nlots of new prose here\n\n" ++ base ++ "\ntrailing words\n";
    const e_prose = try extractor.extractSource(a, "doc.md", with_prose);
    try expectEqualStrings(id_base, e_prose.cases[0].id);

    // Changing the grouped block content changes the durable id.
    const changed = "```zig test\ntest \"b\" { try @import(\"std\").testing.expect(false); }\n```\n";
    const e_changed = try extractor.extractSource(a, "doc.md", changed);
    try expect(!std.mem.eql(u8, id_base, e_changed.cases[0].id));

    // Adding an explicit case label changes the durable id.
    const labeled = "```zig test case:alpha\ntest \"a\" { try @import(\"std\").testing.expect(true); }\n```\n";
    const e_labeled = try extractor.extractSource(a, "doc.md", labeled);
    try expect(!std.mem.eql(u8, id_base, e_labeled.cases[0].id));
}

test "property: duplicate and ambiguous diagnostics are stable across runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const dup = try readFixture(a, "test/fixtures/doctest/extraction/duplicate.md");
    const orphan = try readFixture(a, "test/fixtures/doctest/extraction/orphan.md");

    inline for (.{ dup, orphan }) |src| {
        const r1 = try extractor.extractSource(a, "doc.md", src);
        const r2 = try extractor.extractSource(a, "doc.md", src);
        try expectEqual(r1.diagnostics.len, r2.diagnostics.len);
        try expect(r1.diagnostics.len >= 1);
        for (r1.diagnostics, r2.diagnostics) |x, y| {
            try expectEqualStrings(x.code, y.code);
            try expectEqual(x.line, y.line);
            try expectEqualStrings(x.message, y.message);
        }
    }
}
