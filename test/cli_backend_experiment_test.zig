const std = @import("std");
const zentinel = @import("zentinel");

const config = zentinel.config;
const zir = zentinel.zir_backend;
const ast_backend = zentinel.ast_backend;
const comparison = zentinel.mutators.comparison;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const sample = @embedFile("fixtures/zir_backend/sample.zig");

fn load(arena: std.mem.Allocator, src: []const u8, diag: *config.Diagnostic) config.Error!config.Config {
    return config.load(arena, src, diag);
}

fn comparisonCandidates(arena: std.mem.Allocator) ![]mutant.Mutant {
    var parsed = try ast_backend.parse(arena, "test/fixtures/zir_backend/sample.zig", sample);
    defer parsed.deinit();
    const ranges = try ast_backend.testDeclRanges(parsed, arena);
    var collector = ast_backend.Collector.init(arena);
    try comparison.collect(&collector, parsed, "test/fixtures/zir_backend/sample.zig", ranges);
    return collector.finish();
}

// --- Config opt-in ---------------------------------------------------------

test "ZIR backend default requires explicit experimental opt-in" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Selecting zir as the default backend without opt-in is rejected.
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena, "[backend]\ndefault = \"zir\"\n", &diag));
    try expectEqualStrings("ZNTL_CONFIG_EXPERIMENTAL_BACKEND", diag.code.token());

    // With explicit opt-in it loads and the opt-in is observable.
    var diag2: config.Diagnostic = .{};
    const cfg = try load(arena, "[backend]\ndefault = \"zir\"\nexperimental = [\"zir\"]\n", &diag2);
    try expectEqualStrings("zir", cfg.backend_default);
    try expect(zir.backendOptedIn(cfg, "zir"));
}

// --- Experimental backend gating -------------------------------------------

test "list-mutants --backend zir is rejected without opt-in and accepted with it" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var d1: config.Diagnostic = .{};
    const cfg_no = try load(arena, "", &d1);
    try expect(!zir.backendOptedIn(cfg_no, "zir"));
    try expectError(error.ExperimentalBackendNotEnabled, zir.experimentalListing(arena, cfg_no, &.{}, "zir"));

    // With opt-in the gate passes and the comparison candidates become
    // experimental ZIR candidates with no diagnostics.
    var d2: config.Diagnostic = .{};
    const cfg_yes = try load(arena, "[backend]\nexperimental = [\"zir\"]\n", &d2);
    const ast = try comparisonCandidates(arena);
    try expect(ast.len > 0);
    const listing = try zir.experimentalListing(arena, cfg_yes, ast, "zir");
    try expectEqual(ast.len, listing.candidates.len);
    try expectEqual(@as(usize, 0), listing.diagnostics.len);
    try expectEqual(mutant.Backend.zir, listing.candidates[0].backend);
    try expectEqual(mutant.BackendStability.experimental, listing.candidates[0].backend_stability);
}

test "air backend is not implemented by task 056 (owned by 057)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var d: config.Diagnostic = .{};
    const cfg = try load(arena, "[backend]\nexperimental = [\"air\"]\n", &d);
    try expectError(error.BackendNotImplemented, zir.experimentalListing(arena, cfg, &.{}, "air"));
}

test "AST remains the default backend and never routes through the experimental gate" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var d: config.Diagnostic = .{};
    const cfg = try load(arena, "", &d);
    try expectEqualStrings("ast", cfg.backend_default);
    try expect(!zir.backendOptedIn(cfg, "zir"));
}
