const std = @import("std");
const zentinel = @import("zentinel");

const config = zentinel.config;
const zir = zentinel.zir_backend;
const ast_backend = zentinel.ast_backend;
const comparison = zentinel.mutators.comparison;
const arithmetic = zentinel.mutators.arithmetic;
const boolean = zentinel.mutators.boolean;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

// The AIR experimental backend was retired (AIR-level mutation mapping is
// infeasible without Zig's SEMA stage; the prototype only relabeled AST
// candidates). AST is the stable default; ZIR is the only experimental backend.

fn load(arena: std.mem.Allocator, src: []const u8, diag: *config.Diagnostic) config.Error!config.Config {
    return config.load(arena, src, diag);
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

test "an unknown backend is rejected by config (e.g. the retired 'air')" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // `air` was a known backend before retirement; it must now be an unknown value.
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena, "[backend]\nexperimental = [\"air\"]\n", &diag));
    try expectEqualStrings("ZNTL_CONFIG_INVALID_VALUE", diag.code.token());
}

// --- Experimental backend gating -------------------------------------------

fn allCandidates(arena: std.mem.Allocator, file: []const u8, src: []const u8) ![]mutant.Mutant {
    const parsed = try ast_backend.parse(arena, file, src);
    const ranges = try ast_backend.testDeclRanges(parsed, arena);
    var collector = ast_backend.Collector.init(arena);
    try comparison.collect(&collector, parsed, file, ranges);
    try arithmetic.collect(&collector, parsed, file, ranges);
    try boolean.collect(&collector, parsed, file, ranges); // a lexical operator for the diagnostic path
    return collector.finish();
}

test "list-mutants --backend zir lowers comparison/arithmetic to real ZIR candidates; lexical operators (boolean_literal) become diagnostics" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Comparison (`a < b`), two arithmetic sites (`a + b`, `a - b`) -- all real ZIR
    // candidates -- and a boolean literal (`true`), which has no ZIR instruction.
    const src = "pub fn f(a: i32, b: i32) i32 {\n    const t = true;\n    if (a < b) return a + b;\n    _ = t;\n    return a - b;\n}\n";
    const files = [_]zentinel.run_command.FileSource{.{ .path = "p.zig", .source = src }};
    const ast_all = try allCandidates(arena, "p.zig", src);

    // The pinned toolchain (3a version guard is exercised separately).
    const zig_ok = zentinel.zig_version.Discovery{ .version = zentinel.zig_version.supported_version };

    // Without opt-in the real ZIR path is gated shut.
    var d_no: config.Diagnostic = .{};
    const cfg_no = try load(arena, "", &d_no);
    try expectError(error.ExperimentalBackendNotEnabled, zir.listFromTrees(arena, cfg_no, zig_ok, &files, ast_all, "zir"));

    // With opt-in: comparison + arithmetic are REAL ZIR-lowered candidates; the
    // boolean literal (lexical, no instruction) is an out-of-report diagnostic.
    var d_yes: config.Diagnostic = .{};
    const cfg_yes = try load(arena, "[backend]\nexperimental = [\"zir\"]\n", &d_yes);
    const listing = try zir.listFromTrees(arena, cfg_yes, zig_ok, &files, ast_all, "zir");

    try expectEqual(@as(usize, 3), listing.candidates.len);
    var cmp_n: usize = 0;
    var arith_n: usize = 0;
    for (listing.candidates) |c| {
        try expectEqual(mutant.Backend.zir, c.backend);
        try expectEqual(mutant.BackendStability.experimental, c.backend_stability);
        if (std.mem.eql(u8, c.operator, "comparison_boundary")) {
            cmp_n += 1;
        } else if (std.mem.eql(u8, c.operator, "arithmetic_add_sub")) {
            arith_n += 1;
        } else {
            try expect(false); // no other operator should be a ZIR candidate here
        }
    }
    try expectEqual(@as(usize, 1), cmp_n);
    try expectEqual(@as(usize, 2), arith_n);

    // boolean_literal is a lexical mutation with no ZIR representation -> diagnostic.
    var bool_diags: usize = 0;
    for (listing.diagnostics) |dg| {
        if (std.mem.eql(u8, dg.operator, "boolean_literal")) bool_diags += 1;
        try expect(!std.mem.eql(u8, dg.operator, "arithmetic_add_sub")); // arithmetic is a candidate now
    }
    try expectEqual(@as(usize, 1), bool_diags);
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

// --- CLI experimental-backend diagnostic note rendering (L26) ---------------
//
// The `list-mutants --backend zir` CLI surfaces unsupported-operator diagnostics
// as stderr `note[...]` lines (the documented behavior, L25). This pins the exact
// bytes so a wiring/format regression fails here (L26).

test "zir backend renders the exact stderr note line for an unsupported diagnostic (L26)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const d = zir.Diagnostic{
        .code = "ZNTL_ZIR_UNSUPPORTED",
        .file = "src/calc.zig",
        .operator = "arithmetic_add_sub",
        .span_start = 122,
        .span_end = 123,
        .reason = "no exact ZIR source mapping",
    };
    try expectEqualStrings(
        "note[ZNTL_ZIR_UNSUPPORTED]: arithmetic_add_sub at src/calc.zig:122..123 (no exact ZIR source mapping)\n",
        try zir.renderDiagnosticNote(a, d),
    );
}
