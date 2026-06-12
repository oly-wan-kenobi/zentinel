const std = @import("std");
const zentinel = @import("zentinel");
const sandbox = zentinel.sandbox;
const mutant = zentinel.mutant;
const ast_backend = zentinel.ast_backend;
const mutators = zentinel.mutators;

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;

const fixture_path = "test/fixtures/sandbox/target.zig";
const read_limit = std.Io.Limit.limited(1 << 20);

fn readFixture(a: std.mem.Allocator) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, fixture_path, a, read_limit);
}

fn plusMutant(source: []const u8) mutant.Mutant {
    const at: u32 = @intCast(std.mem.indexOf(u8, source, "a + b").? + 2); // the `+`
    return .{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = "arithmetic_add_sub",
        .operator_stability = .stable,
        .file = "target.zig",
        .span = .{ .byte_start = at, .byte_end = at + 1, .line_start = 2, .column_start = 14, .line_end = 2, .column_end = 15 },
        .original = "+",
        .replacement = "-",
        .expected_compile = .may_fail,
    };
}

test "applies a single mutation to a copied workspace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try readFixture(a);
    const patched = try sandbox.apply(a, source, plusMutant(source));
    try expect(std.mem.indexOf(u8, patched, "a - b") != null);
    try expect(std.mem.indexOf(u8, patched, "a + b") == null);

    // Write the patched copy into an isolated workspace and read it back.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "target.zig", .data = patched });
    const back = try tmp.dir.readFileAlloc(std.testing.io, "target.zig", a, read_limit);
    try expectEqualStrings(patched, back);
}

test "original source file is not modified by patching" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const before = try readFixture(a);
    _ = try sandbox.apply(a, before, plusMutant(before)); // produces a copy; never writes the source
    const after = try readFixture(a);
    try expectEqualStrings(before, after);
}

test "invalid spans produce invalid-ready sandbox diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try readFixture(a);

    var out_of_range = plusMutant(source);
    out_of_range.span.byte_end = @intCast(source.len + 10);
    try expectError(error.SpanOutOfRange, sandbox.apply(a, source, out_of_range));
    try expectEqualStrings("ZNTL_SANDBOX_PATCH_OUT_OF_RANGE", sandbox.code(error.SpanOutOfRange));
    try expect(std.mem.startsWith(u8, sandbox.failureSummary(error.SpanOutOfRange), "sandbox:"));

    var mismatch = plusMutant(source);
    mismatch.original = "X"; // the span text is `+`, not `X`
    try expectError(error.PatchMismatch, sandbox.apply(a, source, mismatch));
    try expectEqualStrings("ZNTL_SANDBOX_PATCH_MISMATCH", sandbox.code(error.PatchMismatch));
    try expect(std.mem.startsWith(u8, sandbox.failureSummary(error.PatchMismatch), "sandbox:"));
}

test "patched content is deterministic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const source = try readFixture(a);
    const m = plusMutant(source);
    const first = try sandbox.apply(a, source, m);
    const second = try sandbox.apply(a, source, m);
    try expectEqualStrings(first, second);
}

// Production code (no `test { ... }` body, so the stable collectors target it)
// containing exactly one untested error path (`catch 0`), one boolean literal
// (`true`), and one comparison-operand integer literal (`3`). These are the
// source-slice (`error_catch_unreachable`, `boolean_literal`) and number-literal
// (`integer_literal_boundary`) operators that capture `Mutant.original` as a
// borrowed slice of the parsed tree's `owned_source`.
const teardown_source =
    \\fn risky(flag: bool) !u8 {
    \\    if (flag) return error.Boom;
    \\    return 7;
    \\}
    \\
    \\pub fn classify(n: u8, flag: bool) u8 {
    \\    const value = risky(flag) catch 0;
    \\    const enabled = true;
    \\    if (n == 3) return value;
    \\    if (enabled) return n;
    \\    return value;
    \\}
;

fn findByOperator(mutants: []const mutant.Mutant, operator: []const u8) ?mutant.Mutant {
    for (mutants) |m| {
        if (std.mem.eql(u8, m.operator, operator)) return m;
    }
    return null;
}

// Regression for adversarial audit finding F-1: a stable operator's
// `Mutant.original` must outlive the parsed tree. This drives the real pipeline
// (parse -> collect -> finish -> `parsed.deinit()` -> `sandbox.apply`), exactly
// like `run_command.generateCandidates`'s `defer parsed.deinit()`, but with a
// poisoning allocator for the parse buffer and a separate long-lived collector
// arena (mirroring the production collector allocator outliving the freed
// source). Before the fix, `original` borrows the freed `owned_source`; on a
// Debug build the freed bytes are poisoned to 0xAA, so `apply` returns
// `PatchMismatch` and the candidate is misclassified `invalid`, hiding a real
// surviving mutant. After the fix the collector owns `original`, so the verdict
// is correct and identical across optimize modes.
test "F-1: stable-operator Mutant.original survives parse teardown" {
    // Long-lived collector storage that outlives the parsed tree.
    var collector_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer collector_arena.deinit();
    const ca = collector_arena.allocator();

    // Parse with the poisoning testing allocator so `parsed.deinit()` actually
    // frees (and in safe modes poisons) `owned_source`.
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", teardown_source);
    const test_ranges = try ast_backend.testDeclRanges(parsed, ca);

    var collector = ast_backend.Collector.init(ca);
    try mutators.error_path.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.boolean.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.integer_boundary.collect(&collector, parsed, "ops.zig", test_ranges);
    const mutants = try collector.finish();

    // Free the parsed tree (and its `owned_source`) before reading `original`,
    // exactly as `generateCandidates` does via `defer parsed.deinit()`.
    parsed.deinit();

    const cases = [_]struct { operator: []const u8, original: []const u8 }{
        .{ .operator = "error_catch_unreachable", .original = "0" },
        .{ .operator = "boolean_literal", .original = "true" },
        .{ .operator = "integer_literal_boundary", .original = "3" },
    };
    for (cases) |c| {
        const m = findByOperator(mutants, c.operator) orelse {
            std.debug.print("F-1: no candidate emitted for operator {s}\n", .{c.operator});
            return error.MissingCandidate;
        };
        // `original` must still equal the real source text at the span; before the
        // fix it points into freed `owned_source`.
        try expectEqualStrings(c.original, m.original);
        // The candidate must apply cleanly against the live source, never dropping
        // to `invalid`. `teardown_source` is a comptime literal (always valid);
        // only the parser's `owned_source` copy was freed.
        const patched = try sandbox.apply(ca, teardown_source, m);
        try expect(!std.mem.eql(u8, patched, teardown_source));
    }
}

// A source exercising EVERY stable source-slice operator, so the teardown guard
// below covers them all -- not just the 3 in F-1. The real-binary integration
// test cannot guard this (its arena's `free` is a no-op rewind that neither frees
// nor poisons), so this GPA-backed test is the actual regression guard for a
// revert of the Collector.add() dup across all operators.
const teardown_all_source =
    \\fn risky(flag: bool) !u8 {
    \\    if (flag) return error.Boom;
    \\    return 7;
    \\}
    \\
    \\fn make(alloc: anytype) !*u8 {
    \\    const p = try alloc.create(u8);
    \\    errdefer alloc.destroy(p);
    \\    p.* = 1;
    \\    return p;
    \\}
    \\
    \\pub fn classify(a: u8, b: u8, flag: bool, opt: ?u8) u8 {
    \\    const sum = a + b;
    \\    const prod = a * b;
    \\    const r = risky(flag) catch 0;
    \\    const enabled = true;
    \\    const fallback = opt orelse 9;
    \\    if (a == 5 and enabled) return sum;
    \\    if (sum < 20) return prod;
    \\    var i: u8 = 0;
    \\    while (i < b) : (i += 1) {}
    \\    for (0..4) |k| {
    \\        _ = k;
    \\    }
    \\    return r + fallback;
    \\}
;

test "every stable source-slice operator's Mutant.original survives parse teardown" {
    var collector_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer collector_arena.deinit();
    const ca = collector_arena.allocator();

    // Parse with the poisoning testing allocator so `parsed.deinit()` actually
    // frees (and in safe modes poisons) `owned_source`; the collector arena is
    // separate and long-lived, mirroring run_command.generateCandidates.
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", teardown_all_source);
    const test_ranges = try ast_backend.testDeclRanges(parsed, ca);

    var collector = ast_backend.Collector.init(ca);
    try mutators.arithmetic.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.comparison.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.logical.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.boolean.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.optional.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.error_path.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.integer_boundary.collect(&collector, parsed, "ops.zig", test_ranges);
    try mutators.loop_boundary.collect(&collector, parsed, "ops.zig", test_ranges);
    const mutants = try collector.finish();

    // Free the parsed tree (and its `owned_source`) before reading `original`,
    // exactly as `generateCandidates` does via `defer parsed.deinit()`.
    parsed.deinit();

    // Every previously-unguarded stable operator must emit a candidate.
    const required_ops = [_][]const u8{
        "arithmetic_add_sub",          "arithmetic_mul_div",
        "equality_swap",               "comparison_boundary",
        "logical_and_or",              "boolean_literal",
        "optional_orelse_unreachable", "error_catch_unreachable",
        "errdefer_remove",             "integer_literal_boundary",
        "loop_boundary",
    };
    for (required_ops) |op| {
        if (findByOperator(mutants, op) == null) {
            std.debug.print("no candidate emitted for operator {s}\n", .{op});
            return error.MissingCandidate;
        }
    }
    try expect(mutants.len >= required_ops.len);

    // EVERY candidate's `original` must still be the live source text -- a
    // substring of the comptime literal, never freed/poisoned bytes -- and must
    // apply cleanly. A revert of the Collector.add() dup fails here for every
    // operator (poisoned `original` is not a substring and breaks sandbox.apply).
    for (mutants) |m| {
        try expect(std.mem.indexOf(u8, teardown_all_source, m.original) != null);
        _ = try sandbox.apply(ca, teardown_all_source, m);
    }
}
