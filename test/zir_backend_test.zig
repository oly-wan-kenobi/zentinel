const std = @import("std");
const zentinel = @import("zentinel");

const ast_backend = zentinel.ast_backend;
const comparison = zentinel.mutators.comparison;
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
