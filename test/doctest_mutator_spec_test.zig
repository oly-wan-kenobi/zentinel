const std = @import("std");
const zentinel = @import("zentinel");
const md = zentinel.doctest.mutator_doctest;
const error_codes = zentinel.error_codes;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const mismatch_snapshot = @embedFile("fixtures/doctest/mutator_spec/mismatch.diagnostic.txt");

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn validateFile(a: std.mem.Allocator, path: []const u8) !md.DocValidation {
    const src = try readFixture(a, path);
    return md.validateDoc(a, path, src);
}

const base = "test/fixtures/doctest/mutator_spec/";

test "arithmetic_add_sub before/after pair matches AST mutator output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = try validateFile(a, base ++ "arithmetic.md");
    try expectEqual(@as(usize, 0), v.diagnostics.len);
    try expectEqual(@as(usize, 1), v.pairs.len);
    try expect(v.pairs[0].matched);
    try expectEqualStrings("arithmetic_add_sub", v.pairs[0].operator);
}

test "comparison_boundary before/after pair matches AST mutator output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = try validateFile(a, base ++ "comparison.md");
    try expectEqual(@as(usize, 1), v.pairs.len);
    try expect(v.pairs[0].matched);
    try expectEqualStrings("comparison_boundary", v.pairs[0].operator);
}

test "boolean_literal before/after pair matches AST mutator output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = try validateFile(a, base ++ "boolean.md");
    try expectEqual(@as(usize, 1), v.pairs.len);
    try expect(v.pairs[0].matched);
    try expectEqualStrings("boolean_literal", v.pairs[0].operator);
}

test "a before block without an after block is an invalid grouping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = try validateFile(a, base ++ "before_only.md");
    try expectEqual(@as(usize, 0), v.pairs.len);
    try expect(v.diagnostics.len >= 1);
    try expectEqualStrings(error_codes.doctest_invalid_block, v.diagnostics[0].code);
}

test "a documented transformation no mutator produces is reported as drift" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = try validateFile(a, base ++ "mismatch.md");
    try expectEqual(@as(usize, 1), v.pairs.len);
    try expect(!v.pairs[0].matched);
    try expectEqual(@as(usize, 1), v.diagnostics.len);
    try expectEqualStrings(error_codes.doctest_snapshot_mismatch, v.diagnostics[0].code);

    const rendered = try md.renderMismatch(a, v.pairs[0]);
    try expectEqualStrings(mismatch_snapshot, rendered);
}

test "unparseable mutator-spec before blocks report backend parse diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const doc =
        \\# invalid mutator spec
        \\
        \\```zig before
        \\const std = @import("std");
        \\test "invalid" {
        \\    try std.testing.expect(true)
        \\}
        \\```
        \\
        \\```zig after
        \\const std = @import("std");
        \\test "invalid" {
        \\    try std.testing.expect(false);
        \\}
        \\```
        \\
    ;
    const v = try md.validateDoc(a, "docs/INVALID_MUTATOR_SPEC.md", doc);
    try expectEqual(@as(usize, 1), v.pairs.len);
    try expect(!v.pairs[0].matched);
    try expectEqual(@as(usize, 1), v.diagnostics.len);
    try expectEqualStrings("ZNTL_BACKEND_PARSE_ERROR", v.diagnostics[0].code);
    try expect(std.mem.indexOf(u8, v.diagnostics[0].message, "could not parse") != null);
}

test "docs/MUTATOR_SPEC.md before/after pairs all match the mutators" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = try validateFile(a, "docs/MUTATOR_SPEC.md");
    try expect(v.pairs.len >= 3);
    for (v.pairs) |p| {
        try expect(p.matched);
    }
    // No drift diagnostics for the live spec.
    for (v.diagnostics) |d| {
        try expect(!std.mem.eql(u8, d.code, error_codes.doctest_snapshot_mismatch));
    }
}

test "validatePair matches a real transformation and rejects an unproduced one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = "fn add(a: i32, b: i32) i32 {\n    return a + b;\n}\n";
    const matched = try md.validatePair(a, before, "fn add(a: i32, b: i32) i32 {\n    return a - b;\n}\n");
    try expect(matched.matched);
    try expectEqualStrings("arithmetic_add_sub", matched.operator);
    const unmatched = try md.validatePair(a, before, "fn add(a: i32, b: i32) i32 {\n    return a * b;\n}\n");
    try expect(!unmatched.matched);
}

test "property: before/after pair ids are stable across repeated validation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v1 = try validateFile(a, base ++ "arithmetic.md");
    const v2 = try validateFile(a, base ++ "arithmetic.md");
    try expectEqualStrings(v1.pairs[0].case_id, v2.pairs[0].case_id);
}

test "property: transformation matching is independent of unrelated prose" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bare = try readFixture(a, base ++ "arithmetic.md");
    const surrounded = try std.fmt.allocPrint(a, "# heading\n\nlots of prose\n\n{s}\ntrailing words\n", .{bare});
    const v1 = try md.validateDoc(a, "doc.md", bare);
    const v2 = try md.validateDoc(a, "doc.md", surrounded);
    try expect(v1.pairs[0].matched and v2.pairs[0].matched);
    try expectEqualStrings(v1.pairs[0].operator, v2.pairs[0].operator);
    // Surrounding prose does not change the durable pair id.
    try expectEqualStrings(v1.pairs[0].case_id, v2.pairs[0].case_id);
}

test "property: multiple pairs keep canonical anchor-line ordering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = try validateFile(a, base ++ "multi.md");
    try expectEqual(@as(usize, 2), v.pairs.len);
    try expect(v.pairs[0].line < v.pairs[1].line);
    for (v.pairs) |p| try expect(p.matched);
}

test "property: mismatch diagnostics are deterministic across runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v1 = try validateFile(a, base ++ "mismatch.md");
    const v2 = try validateFile(a, base ++ "mismatch.md");
    try expectEqual(v1.diagnostics.len, v2.diagnostics.len);
    try expectEqualStrings(v1.diagnostics[0].code, v2.diagnostics[0].code);
    try expectEqual(v1.diagnostics[0].line, v2.diagnostics[0].line);
    try expectEqualStrings(try md.renderMismatch(a, v1.pairs[0]), try md.renderMismatch(a, v2.pairs[0]));
}
