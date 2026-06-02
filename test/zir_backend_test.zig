const std = @import("std");
const zentinel = @import("zentinel");

const ast_backend = zentinel.ast_backend;
const comparison = zentinel.mutators.comparison;
const logical = zentinel.mutators.logical;
const arithmetic = zentinel.mutators.arithmetic;
const zir = zentinel.zir_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const sample = @embedFile("fixtures/zir_backend/sample.zig");
const diagnostics_fixture = @embedFile("fixtures/zir_backend/unsupported_diagnostics.json");

fn astCandidates(arena: std.mem.Allocator, comptime which: enum { comparison, arithmetic }) ![]mutant.Mutant {
    var parsed = try ast_backend.parse(arena, "test/fixtures/zir_backend/sample.zig", sample);
    defer parsed.deinit();
    try expect(parsed.ok());
    const ranges = try ast_backend.testDeclRanges(parsed, arena);
    var collector = ast_backend.Collector.init(arena);
    switch (which) {
        .comparison => try comparison.collect(&collector, parsed, "test/fixtures/zir_backend/sample.zig", ranges),
        .arithmetic => try arithmetic.collect(&collector, parsed, "test/fixtures/zir_backend/sample.zig", ranges),
    }
    return collector.finish();
}

test "ZIR re-tags exactly-mapped AST candidates as experimental with source parity" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const ast = try astCandidates(arena, .comparison);
    try expect(ast.len > 0);

    const result = try zir.fromAst(arena, ast);
    // Every comparison candidate maps exactly, so all are supported and there
    // are no diagnostics.
    try expectEqual(ast.len, result.candidates.len);
    try expectEqual(@as(usize, 0), result.diagnostics.len);

    for (result.candidates, ast) |z, a| {
        // Backend identity is ZIR/experimental, never the stable AST default.
        try expectEqual(mutant.Backend.zir, z.backend);
        try expectEqual(mutant.BackendStability.experimental, z.backend_stability);
        try expectEqualStrings(zir.backend_version, z.backend_version);
        // Parity: exact source mapping (span/operator/original/replacement) is
        // inherited from the AST candidate.
        try expectEqual(a.span.byte_start, z.span.byte_start);
        try expectEqual(a.span.byte_end, z.span.byte_end);
        try expectEqualStrings(a.operator, z.operator);
        try expectEqualStrings(a.original, z.original);
        try expectEqualStrings(a.replacement, z.replacement);
        // The durable id differs because the backend_version is part of identity.
        try expect(!std.mem.eql(u8, a.id, z.id));
        // The re-tagged candidate is still a structurally valid candidate.
        try expect(z.isValidCandidate(sample.len));
    }
}

test "ZIR records unsupported operators as out-of-report diagnostics, never mutants" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const ast = try astCandidates(arena, .arithmetic);
    try expect(ast.len > 0);

    const result = try zir.fromAst(arena, ast);
    // Arithmetic literal rewrites have no exact ZIR source mapping in the
    // prototype, so they become diagnostics and never executable mutants.
    try expectEqual(@as(usize, 0), result.candidates.len);
    try expectEqual(ast.len, result.diagnostics.len);
    try expectEqualStrings("arithmetic_add_sub", result.diagnostics[0].operator);
    try expectEqualStrings("ZNTL_ZIR_UNSUPPORTED", result.diagnostics[0].code);

    // The diagnostics serialize to the committed out-of-report artifact bytes.
    const json = try zir.diagnosticsToJson(arena, result.diagnostics);
    try expectEqualStrings(diagnostics_fixture, json);
}

test "isSupported partitions condition operators from literal/arithmetic operators" {
    try expect(zir.isSupported("comparison_boundary"));
    try expect(zir.isSupported("equality_swap"));
    try expect(zir.isSupported("logical_and_or"));
    try expect(zir.isSupported("boolean_literal"));
    try expect(!zir.isSupported("arithmetic_add_sub"));
    try expect(!zir.isSupported("integer_literal_boundary"));
}

// --- Real ZIR lowering: differential parity with the AST recognizer ----------

fn astComparisonOf(arena: std.mem.Allocator, file: []const u8, source: []const u8) ![]mutant.Mutant {
    const parsed = try ast_backend.parse(arena, file, source);
    const ranges = try ast_backend.testDeclRanges(parsed, arena);
    var collector = ast_backend.Collector.init(arena);
    try comparison.collect(&collector, parsed, file, ranges);
    return collector.finish();
}

test "fromTree lowers source to ZIR and matches the AST comparison set exactly (differential parity)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const fixtures = [_][]const u8{
        // plain comparisons
        "pub fn f(a: i32, b: i32) bool {\n    if (a == b) return true;\n    if (a < b) return false;\n    return a != b;\n}\n",
        // all six operators
        "pub fn g(a: i32, b: i32) i32 {\n    if (a == b) return 0;\n    if (a != b) return 1;\n    if (a < b) return 2;\n    if (a <= b) return 3;\n    if (a > b) return 4;\n    if (a >= b) return 5;\n    return 6;\n}\n",
        // nested fns + generic struct (multi-decl source mapping); no and/or here so
        // this stays a pure comparison-parity fixture (logical is covered separately)
        "fn outer(a: i32, b: i32) bool {\n    return a < b;\n}\nfn Gen(comptime T: type) type {\n    return struct {\n        fn cmp(x: T, y: T) bool {\n            return x == y;\n        }\n    };\n}\npub fn use() bool {\n    _ = Gen(u8).cmp(3, 4);\n    return outer(1, 2);\n}\n",
        // `== null` is excluded by BOTH backends (left to optional_null_check)
        "pub fn n(x: ?u8) bool {\n    return x == null;\n}\n",
        // comparison inside a test body is excluded by BOTH; the one outside is kept
        "pub fn h(a: i32, b: i32) bool {\n    return a > b;\n}\ntest \"t\" {\n    _ = (1 == 2);\n}\n",
        // for-loop + switch inject ZIR comparisons with no source operator: the
        // injected cmps must be DROPPED, leaving only the real `acc > 100`.
        "pub fn s(xs: []const u8) u32 {\n    var acc: u32 = 0;\n    for (xs) |x| {\n        switch (x) {\n            0...9 => acc += 1,\n            else => acc += 2,\n        }\n        if (acc > 100) break;\n    }\n    return acc;\n}\n",
    };

    inline for (fixtures, 0..) |src, fi| {
        const file = "p.zig";
        const ast = try astComparisonOf(arena, file, src);
        const result = try zir.fromTree(arena, file, src);

        // Exact differential parity: the ZIR backend independently recognized and
        // mapped the SAME comparison sites the AST recognizer found -- same count,
        // operator, span, original text, and replacement -- just re-tagged .zir.
        try expectEqual(ast.len, result.candidates.len);
        for (ast, result.candidates) |a, z| {
            try expectEqual(mutant.Backend.zir, z.backend);
            try expectEqual(mutant.BackendStability.experimental, z.backend_stability);
            try expectEqualStrings(zir.backend_version, z.backend_version);
            try expectEqualStrings(a.operator, z.operator);
            try expectEqual(a.span.byte_start, z.span.byte_start);
            try expectEqual(a.span.byte_end, z.span.byte_end);
            try expectEqualStrings(a.original, z.original);
            try expectEqualStrings(a.replacement, z.replacement);
        }
        // fixture index 5 (for/switch) must have produced injected-comparison
        // diagnostics that were dropped from the mutant set, proving ZIR did real
        // lowering rather than just echoing the AST candidates.
        if (fi == 5) try expect(result.diagnostics.len > 0);
    }
}

fn astCmpAndLogicalOf(arena: std.mem.Allocator, file: []const u8, source: []const u8) ![]mutant.Mutant {
    const parsed = try ast_backend.parse(arena, file, source);
    const ranges = try ast_backend.testDeclRanges(parsed, arena);
    var collector = ast_backend.Collector.init(arena);
    try comparison.collect(&collector, parsed, file, ranges);
    try logical.collect(&collector, parsed, file, ranges);
    return collector.finish();
}

test "fromTree also lowers short-circuit and/or in parity with the AST logical recognizer (Phase 2)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const fixtures = [_][]const u8{
        // plain and / chained or
        "pub fn f(a: bool, b: bool) bool {\n    return a and b;\n}\n",
        "pub fn g(a: bool, b: bool, c: bool) bool {\n    return a or b or c;\n}\n",
        // mixed comparison + logical in one expression
        "pub fn m(x: i32, y: i32) bool {\n    return x == y and x < y;\n}\n",
        // nested fn, if/while conditions, mixed comparison + logical (note: the
        // `true`/`false` args are boolean literals -- correctly absent from both sides)
        "fn inner(a: bool, b: bool) bool {\n    return a and b;\n}\npub fn use(x: i32, y: i32) bool {\n    if (x < y or inner(true, false)) return true;\n    return x != y;\n}\n",
        // and/or inside a test body is excluded by BOTH backends; the one outside is kept
        "pub fn h(a: bool, b: bool) bool {\n    return a or b;\n}\ntest \"t\" {\n    _ = (true and false);\n}\n",
    };

    inline for (fixtures) |src| {
        const file = "p.zig";
        const ast = try astCmpAndLogicalOf(arena, file, src);
        const result = try zir.fromTree(arena, file, src);

        try expectEqual(ast.len, result.candidates.len);
        for (ast, result.candidates) |a, z| {
            try expectEqual(mutant.Backend.zir, z.backend);
            try expectEqualStrings(a.operator, z.operator);
            try expectEqual(a.span.byte_start, z.span.byte_start);
            try expectEqual(a.span.byte_end, z.span.byte_end);
            try expectEqualStrings(a.original, z.original);
            try expectEqualStrings(a.replacement, z.replacement);
        }
    }
}
