// Audit-cluster regression tests for the `mutators` finding set:
//   [L3]  integer/loop boundary: out-of-width decimals are parsed as u128 (not
//         dropped wholesale), so a literal between i128 max and u128 max keeps its
//         -1 boundary; only the individually unrepresentable boundary is skipped.
//   [L4]  null-operand detection is node-based and shared: `x == (null)` /
//         `(null) == x` are OWNED by optional_null_check and SKIPPED by
//         equality_swap (AST) and the ZIR backend, so the recognizers agree.
//   [ZIR-flood] one aggregate injected-comparison diagnostic (with a count) per
//         fromTree, not one span-less duplicate per instruction.
//   [mutant-dedupe] sortAndDedupe still removes exact-identity and cross-operator
//         physical-edit duplicates after the allocation reorder.
const std = @import("std");
const zentinel = @import("zentinel");

const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;
const zir = zentinel.zir_backend;
const optional = zentinel.mutators.optional;
const comparison = zentinel.mutators.comparison;
const integer_boundary = zentinel.mutators.integer_boundary;
const loop_boundary = zentinel.mutators.loop_boundary;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn collectOne(
    a: std.mem.Allocator,
    parsed: ast_backend.Parsed,
    comptime collectFn: anytype,
    file: []const u8,
) ![]mutant.Mutant {
    const ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try collectFn(&collector, parsed, file, ranges);
    return collector.finish();
}

// --- [L3] out-of-width decimals are kept (parsed as u128) --------------------

test "[L3] integer_boundary: a decimal above i128 max but within u128 keeps its -1 boundary (was dropped wholesale)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 2e38 is > i128 max (~1.70e38) but < u128 max (~3.40e38). The old
    // `parseInt(i128) catch return` discarded this legal literal entirely; with
    // u128 the +1 boundary overflows nothing here, so BOTH boundaries are emitted.
    var parsed = try ast_backend.parse(std.testing.allocator, "big.zig",
        \\pub fn f(x: u128) bool {
        \\    return x < 200000000000000000000000000000000000000;
        \\}
    );
    defer parsed.deinit();
    const c = try collectOne(a, parsed, integer_boundary.collect, "big.zig");

    try expectEqual(@as(usize, 2), c.len);
    for (c) |m| {
        try expectEqualStrings("integer_literal_boundary", m.operator);
        try expectEqualStrings("200000000000000000000000000000000000000", m.original);
    }
    // Canonical order sorts by replacement string: "1999..." (-1) before "2000...001" (+1).
    try expectEqualStrings("199999999999999999999999999999999999999", c[0].replacement);
    try expectEqualStrings("200000000000000000000000000000000000001", c[1].replacement);
}

test "[L3] integer_boundary: the u128-max literal still drops only the overflowing +1 boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // u128 max = 340282366920938463463374607431768211455. +1 overflows u128 and is
    // skipped; the -1 boundary is emitted. (Previously this parsed as i128 and was
    // dropped wholesale, since u128 max does not fit i128.)
    var parsed = try ast_backend.parse(std.testing.allocator, "umax.zig",
        \\pub fn f(x: u128) bool {
        \\    return x == 340282366920938463463374607431768211455;
        \\}
    );
    defer parsed.deinit();
    const c = try collectOne(a, parsed, integer_boundary.collect, "umax.zig");

    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("340282366920938463463374607431768211455", c[0].original);
    try expectEqualStrings("340282366920938463463374607431768211454", c[0].replacement);
}

test "[L3] integer_boundary: a decimal above u128 max is still skipped (does not panic)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 5e38 exceeds u128 max (~3.40e38): parseInt(u128) fails and the literal is
    // skipped via `catch return`, exactly as the old i128 path skipped its own
    // out-of-width decimals -- no candidate, no panic.
    var parsed = try ast_backend.parse(std.testing.allocator, "huge.zig",
        \\pub fn f(x: u128) bool {
        \\    return x < 500000000000000000000000000000000000000;
        \\}
    );
    defer parsed.deinit();
    const c = try collectOne(a, parsed, integer_boundary.collect, "huge.zig");
    try expectEqual(@as(usize, 0), c.len);
}

test "[L3] loop_boundary: a for-range end above i128 max but within u128 keeps its -1 boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "r.zig",
        \\pub fn f() void {
        \\    for (0..200000000000000000000000000000000000000) |i| {
        \\        _ = i;
        \\    }
        \\}
    );
    defer parsed.deinit();
    const c = try collectOne(a, parsed, loop_boundary.collect, "r.zig");

    try expectEqual(@as(usize, 2), c.len);
    for (c) |m| {
        try expectEqualStrings("loop_boundary", m.operator);
        try expectEqualStrings("200000000000000000000000000000000000000", m.original);
    }
    try expectEqualStrings("199999999999999999999999999999999999999", c[0].replacement);
    try expectEqualStrings("200000000000000000000000000000000000001", c[1].replacement);
}

// --- [L4] node-based shared null recognizer ----------------------------------

test "[L4] optional OWNS `x == (null)` and `(null) == x` (grouped null unwrapped)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/optional/grouped_null.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "grouped_null.zig", src);
    defer parsed.deinit();
    const c = try collectOne(a, parsed, optional.collect, "grouped_null.zig");

    // Both parenthesized null comparisons are emitted as optional_null_check swaps.
    try expectEqual(@as(usize, 2), c.len);
    for (c) |m| {
        try expectEqualStrings("optional_null_check", m.operator);
        try expectEqualStrings("==", m.original);
        try expectEqualStrings("!=", m.replacement);
        try expectEqual(mutant.ExpectedCompile.compiles, m.expected_compile);
    }
}

test "[L4] equality_swap SKIPS `x == (null)` and `(null) == x` (left to optional_null_check)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/comparison/grouped_null.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "grouped_null.zig", src);
    defer parsed.deinit();
    const c = try collectOne(a, parsed, comparison.collect, "grouped_null.zig");

    // The comparison mutator emits NOTHING for parenthesized null comparisons --
    // the two recognizers now agree on `(null)` (positional check disagreed).
    try expectEqual(@as(usize, 0), c.len);
}

test "[L4] doubly-parenthesized `x != ((null))` is still recognized as a null comparison" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "dd.zig",
        \\pub fn f(x: ?i32) bool {
        \\    return x != ((null));
        \\}
    );
    defer parsed.deinit();

    const opt = try collectOne(a, parsed, optional.collect, "dd.zig");
    try expectEqual(@as(usize, 1), opt.len);
    try expectEqualStrings("optional_null_check", opt[0].operator);
    try expectEqualStrings("!=", opt[0].original);
    try expectEqualStrings("==", opt[0].replacement);

    const cmp = try collectOne(a, parsed, comparison.collect, "dd.zig");
    try expectEqual(@as(usize, 0), cmp.len);
}

test "[L4] a parenthesized non-null operand `(x) == (y)` is still a real equality_swap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The shared recognizer only treats `null` as null; a parenthesized ordinary
    // operand must not be mistaken for null, so equality_swap still owns this.
    var parsed = try ast_backend.parse(std.testing.allocator, "nn.zig",
        \\pub fn f(x: i32, y: i32) bool {
        \\    return (x) == (y);
        \\}
    );
    defer parsed.deinit();

    const cmp = try collectOne(a, parsed, comparison.collect, "nn.zig");
    try expectEqual(@as(usize, 1), cmp.len);
    try expectEqualStrings("equality_swap", cmp[0].operator);

    const opt = try collectOne(a, parsed, optional.collect, "nn.zig");
    try expectEqual(@as(usize, 0), opt.len);
}

test "[L4] the ZIR backend also SKIPS `x == (null)` (shared recognizer parity with the AST)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The ZIR backend lowers `cmp_eq`/`cmp_neq` but must leave null comparisons to
    // optional_null_check using the SAME node-based recognizer; otherwise ZIR would
    // emit an equality_swap the AST backend does not (a differential divergence).
    const src =
        \\pub fn f(x: ?i32) bool {
        \\    return x == (null);
        \\}
    ;
    const res = try zir.fromTree(a, "z.zig", src);
    for (res.candidates) |z| {
        try expect(!std.mem.eql(u8, z.operator, "equality_swap"));
    }
}

// --- [ZIR-flood] one aggregate injected-comparison diagnostic ----------------

test "[ZIR-flood] for/switch fromTree emits exactly ONE aggregate injected diagnostic carrying a count" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A for-loop + switch inject several ZIR comparisons with no source operator.
    // Pre-fix each emitted its own span-less note (stderr flood); now they collapse
    // into a single `operator = "injected"` diagnostic whose reason embeds the count.
    const src =
        \\pub fn s(xs: []const u8) u32 {
        \\    var acc: u32 = 0;
        \\    for (xs) |x| {
        \\        switch (x) {
        \\            0...9 => acc += 1,
        \\            else => acc += 2,
        \\        }
        \\        if (acc > 100) break;
        \\    }
        \\    return acc;
        \\}
    ;
    const res = try zir.fromTree(a, "s.zig", src);

    // The test contract (zir_backend_test.zig) still holds: diagnostics is non-empty.
    try expect(res.diagnostics.len > 0);

    var injected: usize = 0;
    for (res.diagnostics) |d| {
        if (std.mem.eql(u8, d.operator, "injected")) {
            injected += 1;
            try expectEqual(@as(u64, 0), d.span_start);
            try expectEqual(@as(u64, 0), d.span_end);
            // The count is embedded in the reason rather than implied by the
            // number of duplicate diagnostics.
            try expect(std.mem.indexOf(u8, d.reason, "no source operator") != null);
        }
    }
    // Exactly one aggregate injected diagnostic, regardless of how many were dropped.
    try expectEqual(@as(usize, 1), injected);
}

// --- [mutant-dedupe] semantics preserved after the allocation reorder --------

fn makeMutant(
    op: []const u8,
    file: []const u8,
    start: u64,
    end: u64,
    original: []const u8,
    replacement: []const u8,
) mutant.Mutant {
    return .{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = op,
        .operator_stability = .stable,
        .file = file,
        .span = .{ .byte_start = start, .byte_end = end, .line_start = 1, .column_start = 1, .line_end = 1, .column_end = @intCast(end - start + 1) },
        .original = original,
        .replacement = replacement,
        .expected_compile = .compiles,
    };
}

test "[mutant-dedupe] exact-identity duplicates collapse (id check precedes edit_key allocation)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var m1 = makeMutant("comparison_boundary", "src/x.zig", 10, 12, "<=", "<");
    var m2 = m1; // identical identity fields -> identical id
    try mutant.assignId(a, &m1);
    try mutant.assignId(a, &m2);
    try expectEqualStrings(m1.id, m2.id);

    const out = try mutant.sortAndDedupe(a, &.{ m1, m2 });
    try expectEqual(@as(usize, 1), out.len);
    try expectEqualStrings("comparison_boundary", out[0].operator);
}

test "[mutant-dedupe] cross-operator same-physical-edit duplicates still collapse (content-based edit_key kept)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two DIFFERENT operators recognize the SAME physical edit (`<` -> `<=` at the
    // same span). Their `original`/`replacement` slices are distinct backing memory
    // with identical content, so the dedupe MUST stay content-based (not pointer
    // identity). Distinct operators -> distinct ids, so only the edit_key path
    // catches this; the canonical-first operator (comparison_boundary) is kept.
    const orig_a = try a.dupe(u8, "<");
    const repl_a = try a.dupe(u8, "<=");
    const orig_b = try a.dupe(u8, "<");
    const repl_b = try a.dupe(u8, "<=");
    try expect(orig_a.ptr != orig_b.ptr); // genuinely different slices

    var m_cmp = makeMutant("comparison_boundary", "src/y.zig", 20, 21, orig_a, repl_a);
    var m_loop = makeMutant("loop_boundary", "src/y.zig", 20, 21, orig_b, repl_b);
    try mutant.assignId(a, &m_cmp);
    try mutant.assignId(a, &m_loop);
    try expect(!std.mem.eql(u8, m_cmp.id, m_loop.id)); // different ids (operator differs)

    const out = try mutant.sortAndDedupe(a, &.{ m_loop, m_cmp });
    try expectEqual(@as(usize, 1), out.len);
    // Canonical order keeps the alphabetically-first operator.
    try expectEqualStrings("comparison_boundary", out[0].operator);
}

test "[mutant-dedupe] distinct edits at the same span (different replacement) are both kept" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // +1 and -1 boundaries of the same literal: same span, different replacement ->
    // genuinely distinct edits that must NOT be deduped.
    var plus = makeMutant("integer_literal_boundary", "src/z.zig", 5, 7, "10", "11");
    var minus = makeMutant("integer_literal_boundary", "src/z.zig", 5, 7, "10", "9");
    try mutant.assignId(a, &plus);
    try mutant.assignId(a, &minus);

    const out = try mutant.sortAndDedupe(a, &.{ plus, minus });
    try expectEqual(@as(usize, 2), out.len);
}
