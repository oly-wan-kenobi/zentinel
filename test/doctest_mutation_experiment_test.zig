const std = @import("std");
const zentinel = @import("zentinel");
const me = zentinel.doctest.mutation_experiment;
const report = zentinel.report;
const proc = zentinel.runner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const report_snapshot = @embedFile("fixtures/doctest/mutation/report.experiment.json");

// A deterministic mock: a mutated snippet whose production function became
// `return a - b` breaks the strong test (exit 1); everything else passes.
const MockRunner = struct {
    fn run(ctx: *anyopaque, mutated: []const u8) proc.RawOutcome {
        _ = ctx;
        const broke = std.mem.indexOf(u8, mutated, "return a - b") != null;
        return .{
            .exit_code = if (broke) 1 else 0,
            .timed_out = false,
            .crashed = false,
            .duration_ms = 0,
            .stdout = "",
            .stderr = if (broke) "doctest assertion failed" else "",
        };
    }
};

fn runner() me.SnippetRunner {
    return .{ .ctx = undefined, .runFn = MockRunner.run };
}

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn runFile(a: std.mem.Allocator, path: []const u8) !me.Report {
    const src = try readFixture(a, path);
    return me.run(a, path, src, runner());
}

const base = "test/fixtures/doctest/mutation/";

test "a strong doctest kills the arithmetic mutant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try runFile(a, base ++ "killed.md");
    try expectEqual(@as(usize, 1), r.cases.len);
    try expect(!r.cases[0].skipped);
    try expectEqual(@as(usize, 1), r.cases[0].mutants.len);
    try expectEqual(report.ResultStatus.killed, r.cases[0].mutants[0].status);
    try expectEqual(@as(u64, 1), r.summary.killed);
}

test "a weak doctest lets the boundary mutant survive" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try runFile(a, base ++ "survived.md");
    // `return a >= 0;` yields a comparison_boundary mutant plus one
    // integer_literal_boundary mutant (0 -> 1) now that the Phase-2 collectors run
    // in the doctest --mutate path. The literal `0`'s -1 boundary underflows the
    // u128 the integer-boundary collector parses into and is dropped (a negative
    // replacement is outside the non-negative decimal-literal model), so two
    // survivors -- not three. The weak test kills neither.
    try expectEqual(@as(usize, 2), r.cases[0].mutants.len);
    for (r.cases[0].mutants) |m| {
        try expectEqual(report.ResultStatus.survived, m.status);
        try expect(m.survivor_ref != null);
    }
    try expectEqual(@as(u64, 2), r.summary.survived);
}

test "doctest --mutate generates Phase-2 mutants for an orelse-only snippet" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The only mutable PRODUCTION construct is a Phase-2 `orelse` fallback (the
    // `==` lives in the test body and is excluded by test-range filtering). Before
    // the fix candidatesOrParseError ran only the 4 Phase-1 collectors, so this
    // emitted ZERO mutants and a genuinely weak doc example looked fully covered
    // -- the exact silent under-reporting the feature exists to prevent.
    const src =
        \\# doc
        \\
        \\```zig test
        \\fn pick(x: ?u32) u32 {
        \\    return x orelse 7;
        \\}
        \\
        \\test "pick falls back" {
        \\    try @import("std").testing.expect(pick(null) == 7);
        \\}
        \\```
        \\
    ;
    const r = try me.run(a, "phase2.md", src, runner());
    try expectEqual(@as(usize, 1), r.cases.len);
    try expect(!r.cases[0].skipped);
    try expect(r.cases[0].mutants.len >= 1);

    // The Phase-2 optional operator is now reachable from the doctest --mutate path.
    var saw_orelse = false;
    for (r.cases[0].mutants) |m| {
        if (std.mem.eql(u8, m.operator, "optional_orelse_unreachable")) saw_orelse = true;
    }
    try expect(saw_orelse);
}

test "a doctest with no behavioral assertion is skipped before mutation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try runFile(a, base ++ "no_assertion.md");
    try expectEqual(@as(usize, 1), r.cases.len);
    try expect(r.cases[0].skipped);
    try expectEqualStrings("no_behavioral_assertion", r.cases[0].skip_reason.?);
    try expectEqual(@as(usize, 0), r.cases[0].mutants.len);
}

test "mutation-aware runner evidence includes failure_kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try runFile(a, base ++ "killed.md");
    const ev = r.cases[0].mutants[0].runner_evidence;
    try expectEqual(report.FailureKind.test_failure, ev.failure_kind);
    try expectEqual(@as(?i64, 1), ev.exit_code);
}

test "property: a normal doctest failure prevents mutation execution for that case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try runFile(a, base ++ "preflight_fail.md");
    try expect(r.cases[0].skipped);
    try expectEqual(@as(usize, 0), r.cases[0].mutants.len);
    try expectEqual(@as(u64, 0), r.summary.mutants);
}

test "mutation experiment JSON report snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try runFile(a, base ++ "report.md");
    const json = try me.toJson(a, r);
    try expectEqualStrings(report_snapshot, json);
}

test "property: report ordering is stable across repeated runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const j1 = try me.toJson(a, try runFile(a, base ++ "report.md"));
    const j2 = try me.toJson(a, try runFile(a, base ++ "report.md"));
    try expectEqualStrings(j1, j2);
}

test "property: mutating a doctest snippet never modifies the documentation file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try readFixture(a, base ++ "killed.md");
    _ = try me.run(a, base ++ "killed.md", before, runner());
    const after = try readFixture(a, base ++ "killed.md");
    try expectEqualStrings(before, after);
}

test "the feature is marked experimental" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try runFile(a, base ++ "killed.md");
    try expect(r.experimental);
    try expectEqualStrings("zentinel.doctest.mutation_experiment.v1", r.schema_version);
}
