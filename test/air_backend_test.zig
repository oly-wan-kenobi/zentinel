const std = @import("std");
const zentinel = @import("zentinel");

const ast_backend = zentinel.ast_backend;
const comparison = zentinel.mutators.comparison;
const arithmetic = zentinel.mutators.arithmetic;
const logical = zentinel.mutators.logical;
const air = zentinel.air_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const sample = @embedFile("fixtures/air_backend/sample.zig");
const diagnostics_fixture = @embedFile("fixtures/air_backend/unsupported_diagnostics.json");

fn candidates(arena: std.mem.Allocator, comptime which: enum { comparison, arithmetic, logical }) ![]mutant.Mutant {
    var parsed = try ast_backend.parse(arena, "test/fixtures/air_backend/sample.zig", sample);
    defer parsed.deinit();
    try expect(parsed.ok());
    const ranges = try ast_backend.testDeclRanges(parsed, arena);
    var collector = ast_backend.Collector.init(arena);
    switch (which) {
        .comparison => try comparison.collect(&collector, parsed, "test/fixtures/air_backend/sample.zig", ranges),
        .arithmetic => try arithmetic.collect(&collector, parsed, "test/fixtures/air_backend/sample.zig", ranges),
        .logical => try logical.collect(&collector, parsed, "test/fixtures/air_backend/sample.zig", ranges),
    }
    return collector.finish();
}

test "AIR supports overflow-sensitive arithmetic and bounds comparisons with exact mapping" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // AIR's supported set differs from ZIR: it covers overflow-sensitive
    // arithmetic in addition to bounds comparisons.
    try expect(air.isSupported("arithmetic_add_sub"));
    try expect(air.isSupported("arithmetic_mul_div"));
    try expect(air.isSupported("comparison_boundary"));
    try expect(air.isSupported("equality_swap"));
    // Control-flow boolean/logical operators are not yet exactly AIR-mappable.
    try expect(!air.isSupported("logical_and_or"));
    try expect(!air.isSupported("boolean_literal"));

    const ast = try candidates(arena, .arithmetic);
    try expect(ast.len > 0);
    const result = try air.fromAst(arena, ast, "Debug");
    try expectEqual(ast.len, result.candidates.len);
    try expectEqual(@as(usize, 0), result.diagnostics.len);
    for (result.candidates, ast) |a, src| {
        try expectEqual(mutant.Backend.air, a.backend);
        try expectEqual(mutant.BackendStability.experimental, a.backend_stability);
        try expectEqualStrings(air.backend_version, a.backend_version);
        // Exact source-mapping parity with AST.
        try expectEqual(src.span.byte_start, a.span.byte_start);
        try expectEqual(src.span.byte_end, a.span.byte_end);
        try expectEqualStrings(src.operator, a.operator);
        try expectEqualStrings(src.original, a.original);
        try expectEqualStrings(src.replacement, a.replacement);
        // Distinct durable id (backend_version is part of identity).
        try expect(!std.mem.eql(u8, src.id, a.id));
        try expect(a.isValidCandidate(sample.len));
    }
}

test "AIR records approximate-mapping operators as out-of-report diagnostics, never mutants" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const ast = try candidates(arena, .logical);
    try expect(ast.len > 0);
    const result = try air.fromAst(arena, ast, "Debug");
    try expectEqual(@as(usize, 0), result.candidates.len);
    try expectEqual(ast.len, result.diagnostics.len);
    try expectEqualStrings("logical_and_or", result.diagnostics[0].operator);
    try expectEqualStrings("ZNTL_AIR_UNSUPPORTED", result.diagnostics[0].code);
    // Only `exact` source mapping may enter the mutant list; a diagnostic is
    // approximate, and it carries the active safety mode.
    try expectEqualStrings("approximate", result.diagnostics[0].source_mapping);
    try expectEqualStrings("Debug", result.diagnostics[0].safety_mode);

    const json = try air.diagnosticsToJson(arena, result.diagnostics, "Debug");
    try expectEqualStrings(diagnostics_fixture, json);
}
