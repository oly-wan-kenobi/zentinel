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

const diagnostics_fixture = @embedFile("fixtures/zir_backend/unsupported_diagnostics.json");

test "diagnosticsToJson serializes out-of-report diagnostics to the committed schema-versioned artifact bytes" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // The serializer is independent of how the diagnostics were produced; feed it a
    // representative out-of-report diagnostic and assert the exact committed bytes
    // (schema_version, backend identity, and the unsupported entry, in field order).
    const diagnostics = [_]zir.Diagnostic{.{
        .file = "test/fixtures/zir_backend/sample.zig",
        .operator = "arithmetic_add_sub",
        .span_start = 122,
        .span_end = 123,
        .reason = "operator has no exact ZIR source mapping in the prototype; needs type-level ZIR context",
    }};
    const json = try zir.diagnosticsToJson(arena, &diagnostics);
    try expectEqualStrings(diagnostics_fixture, json);
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

fn astLoweredOf(arena: std.mem.Allocator, file: []const u8, source: []const u8) ![]mutant.Mutant {
    const parsed = try ast_backend.parse(arena, file, source);
    const ranges = try ast_backend.testDeclRanges(parsed, arena);
    var collector = ast_backend.Collector.init(arena);
    try comparison.collect(&collector, parsed, file, ranges);
    try logical.collect(&collector, parsed, file, ranges);
    try arithmetic.collect(&collector, parsed, file, ranges);
    return collector.finish();
}

test "fromTree also lowers arithmetic (+,-,*,/) in parity with the AST recognizer, incl. expected_compile=may_fail (Phase 3)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const fixtures = [_][]const u8{
        // plain arithmetic (note arithmetic_*'s expected_compile is may_fail, not compiles)
        "pub fn f(a: i32, b: i32) i32 {\n    return a + b * 2 - a;\n}\n",
        // mixed arithmetic + comparison + logical in one expression
        "pub fn m(a: i32, b: i32) bool {\n    return a + b < a * b and a - b > 0;\n}\n",
        // nested fn + array index expression (a real source `+`, not injected)
        "fn g(xs: []const i32, i: usize) i32 {\n    return xs[i + 1] * 2;\n}\npub fn use(a: i32) i32 {\n    return g(&[_]i32{a}, 0) - a;\n}\n",
        // arithmetic inside a test body is excluded by BOTH backends; the one outside is kept
        "pub fn h(a: i32, b: i32) i32 {\n    return a * b;\n}\ntest \"t\" {\n    _ = (1 + 2);\n}\n",
    };

    inline for (fixtures) |src| {
        const file = "p.zig";
        const ast = try astLoweredOf(arena, file, src);
        const result = try zir.fromTree(arena, file, src);

        try expectEqual(ast.len, result.candidates.len);
        for (ast, result.candidates) |a, z| {
            try expectEqual(mutant.Backend.zir, z.backend);
            try expectEqualStrings(a.operator, z.operator);
            try expectEqual(a.span.byte_start, z.span.byte_start);
            try expectEqual(a.span.byte_end, z.span.byte_end);
            try expectEqualStrings(a.original, z.original);
            try expectEqualStrings(a.replacement, z.replacement);
            // arithmetic candidates carry expected_compile = .may_fail, comparison/logical .compiles
            try expectEqual(a.expected_compile, z.expected_compile);
        }
    }
}

// --- ZIR-1: comptime-context-aware expected_compile --------------------------

test "fromTree downgrades expected_compile for a comparison inside a comptime block; the runtime one stays .compiles (ZIR-1)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const file = "p.zig";
    // Two comparison_boundary sites (`<` and `>`, both normally .compiles): one in a
    // runtime fn (line 2) and one inside a `comptime { ... }` block (line 6). Distinct
    // operators are used on purpose so each maps to its own AST node -- two identical
    // operators would collide in the resolver's innermost-base heuristic (a separate,
    // pre-existing limitation that ZIR-3 hardens), which is orthogonal to this test.
    const src =
        "pub fn rt(a: i32, b: i32) bool {\n" ++ // line 1
        "    return a < b;\n" ++ // line 2 -- runtime comparison (`<`)
        "}\n" ++ // line 3
        "pub fn ct(comptime a: i32, comptime b: i32) bool {\n" ++ // line 4
        "    comptime {\n" ++ // line 5
        "        return a > b;\n" ++ // line 6 -- comptime comparison (`>`)
        "    }\n" ++ // line 7
        "}\n"; // line 8

    const result = try zir.fromTree(arena, file, src);

    var runtime_seen = false;
    var comptime_seen = false;
    for (result.candidates) |c| {
        // Both `<` and `>` are the comparison_boundary operator.
        try expectEqualStrings("comparison_boundary", c.operator);
        if (c.span.line_start == 2) {
            runtime_seen = true;
            try expectEqualStrings("<", c.original);
            // Runtime context: the swap compiles, exactly as the AST recognizer says.
            try expectEqual(mutant.ExpectedCompile.compiles, c.expected_compile);
        } else if (c.span.line_start == 6) {
            comptime_seen = true;
            try expectEqualStrings(">", c.original);
            // Inside `comptime { ... }` the swap is comptime-evaluated: strict, so
            // .compiles is downgraded to .may_fail. (Red before ZIR-1: was .compiles.)
            try expectEqual(mutant.ExpectedCompile.may_fail, c.expected_compile);
        } else {
            return error.UnexpectedCandidate;
        }
    }
    try expect(runtime_seen);
    try expect(comptime_seen);
}

// --- ZIR-2: differential oracle (ZIR vs AST) ---------------------------------

test "differentialOracle: an agreeing file has no divergence; dropping one AST site flags exactly that (operator, span) as zir_only (ZIR-2)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const file = "p.zig";
    // Three binary-operator sites both recognizers agree on: `<`, `and`, `==`.
    const src = "pub fn f(a: i32, b: i32) bool {\n    return a < b and a == b;\n}\n";
    const ast = try astCmpAndLogicalOf(arena, file, src);
    try expect(ast.len >= 3);

    // Agreement: the AST candidate set and ZIR's independent lowering match exactly,
    // so the oracle reports nothing.
    const agree = try zir.differentialOracle(arena, file, src, ast);
    try expectEqual(@as(usize, 0), agree.len);

    // Perturb the AST set: drop one site, as if an AST mutator regressed and missed it.
    // The oracle must flag exactly that site -- present in ZIR's lowering, absent from
    // the (perturbed) AST set -- as a zir_only divergence, and report nothing else.
    const dropped = ast[0];
    const perturbed = ast[1..];
    const found = try zir.differentialOracle(arena, file, src, perturbed);

    var flagged = false;
    for (found) |d| {
        try expectEqualStrings(file, d.file);
        try expectEqualStrings(dropped.operator, d.operator);
        try expectEqual(dropped.span.byte_start, d.span_start);
        try expectEqual(dropped.span.byte_end, d.span_end);
        try expectEqual(zir.DivergenceSide.zir_only, d.side);
        flagged = true;
    }
    try expect(flagged);
}

// --- ZIR-3 / 3a: version guard -----------------------------------------------

test "listFromTrees declines on a non-pinned toolchain and accepts Zig 0.16.0 (ZIR-3 / 3a)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const file = "p.zig";
    const src = "pub fn f(a: i32, b: i32) bool {\n    return a < b;\n}\n";
    const files = [_]zentinel.run_command.FileSource{.{ .path = file, .source = src }};
    const ast = try astComparisonOf(arena, file, src);

    var diag: zentinel.config.Diagnostic = .{};
    const cfg = try zentinel.config.load(arena, "[backend]\nexperimental = [\"zir\"]\n", &diag);

    // The ZIR path's src_node decoding is coupled to the pinned Zig; a different
    // toolchain, a same-version nightly, or a missing Zig all decline.
    const older = zentinel.zig_version.Discovery{ .version = "0.15.0" };
    try std.testing.expectError(error.UnsupportedZigVersion, zir.listFromTrees(arena, cfg, older, &files, ast, "zir"));
    const nightly = zentinel.zig_version.Discovery{ .version = "0.16.0-dev.42" };
    try std.testing.expectError(error.UnsupportedZigVersion, zir.listFromTrees(arena, cfg, nightly, &files, ast, "zir"));
    try std.testing.expectError(error.UnsupportedZigVersion, zir.listFromTrees(arena, cfg, .not_found, &files, ast, "zir"));

    // The pinned version is accepted and the `<` is lowered to a real ZIR candidate.
    const pinned = zentinel.zig_version.Discovery{ .version = zentinel.zig_version.supported_version };
    const listing = try zir.listFromTrees(arena, cfg, pinned, &files, ast, "zir");
    var saw_cmp = false;
    for (listing.candidates) |c| {
        if (std.mem.eql(u8, c.operator, "comparison_boundary") and std.mem.eql(u8, c.original, "<")) saw_cmp = true;
    }
    try expect(saw_cmp);
}

// --- ZIR-3 / 3c: resolution-bijection audit ----------------------------------

test "fromTree flags a non-bijective instruction->node resolution as an anomaly; a clean file has none (ZIR-3 / 3c)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const anomaly_code = "ZNTL_ZIR_RESOLUTION_ANOMALY";

    // Clean: distinct operators map to distinct AST nodes -> no resolution anomaly.
    const clean = "pub fn f(a: i32, b: i32) bool {\n    return a < b and a > b;\n}\n";
    const clean_res = try zir.fromTree(arena, "p.zig", clean);
    for (clean_res.diagnostics) |d| {
        try expect(!std.mem.eql(u8, d.code, anomaly_code));
    }

    // Forced collision: two identical functions whose `<` sites sit at equal
    // decl-relative offsets, so the innermost-base heuristic resolves BOTH ZIR
    // instructions to the same AST node. The audit must surface exactly one anomaly,
    // flagged at a `<` operator token.
    const collide = "pub fn p(a: i32, b: i32) bool {\n    return a < b;\n}\npub fn q(a: i32, b: i32) bool {\n    return a < b;\n}\n";
    const collide_res = try zir.fromTree(arena, "p.zig", collide);
    var anomalies: usize = 0;
    for (collide_res.diagnostics) |d| {
        if (!std.mem.eql(u8, d.code, anomaly_code)) continue;
        anomalies += 1;
        try expectEqualStrings("resolution_anomaly", d.operator);
        // The flagged span is exactly a `<` operator token, not a placeholder.
        try expectEqualStrings("<", collide[@intCast(d.span_start)..@intCast(d.span_end)]);
    }
    try expect(anomalies == 1);
}
