const std = @import("std");
const zentinel = @import("zentinel");
const error_path = zentinel.mutators.error_path;
const ast_backend = zentinel.ast_backend;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFixture(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

fn collectErrorPath(a: std.mem.Allocator, parsed: ast_backend.Parsed) ![]mutant.Mutant {
    const test_ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try error_path.collect(&collector, parsed, "ops.zig", test_ranges);
    return collector.finish();
}

test "catch handler -> catch unreachable in canonical order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/error_path/ops.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", src);
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);

    // parseOr (catch 0) and handled (catch -1); alreadyUnreachable is skipped.
    try expectEqual(@as(usize, 2), c.len);

    try expectEqualStrings("error_catch_unreachable", c[0].operator);
    try expectEqualStrings("0", c[0].original);
    try expectEqualStrings("unreachable", c[0].replacement);
    try expectEqual(mutant.ExpectedCompile.may_fail, c[0].expected_compile);

    try expectEqualStrings("error_catch_unreachable", c[1].operator);
    try expectEqualStrings("-1", c[1].original);
    try expectEqualStrings("unreachable", c[1].replacement);

    try expect(c[0].span.byte_start < c[1].span.byte_start);
    try expect(std.mem.startsWith(u8, c[0].id, "m_"));
    try expect(c[0].backend == .ast and c[0].backend_stability == .stable);
    try expect(c[0].equivalent_risks.len > 0);
}

test "an existing catch unreachable is not mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "cu.zig",
        \\pub fn f(e: anyerror!i32) i32 {
        \\    return e catch unreachable;
        \\}
    );
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "a catch with an |err| payload replaces the capture and handler together" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "p.zig",
        \\pub fn f(e: anyerror!i32) i32 {
        \\    return e catch |err| handle(err);
        \\}
        \\fn handle(_: anyerror) i32 {
        \\    return -1;
        \\}
    );
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("error_catch_unreachable", c[0].operator);
    // The span covers the `|err|` capture AND the handler, so the replacement
    // `unreachable` yields the valid `catch unreachable` rather than orphaning the
    // capture into `catch |err| unreachable` (an `unused capture` error) (M1).
    try expectEqualStrings("|err| handle(err)", c[0].original);
    try expectEqualStrings("unreachable", c[0].replacement);
}

test "survivor fixture: never-exercised error path yields a catch candidate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/error_path/survivor.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "survivor.zig", src);
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("error_catch_unreachable", c[0].operator);
    try expectEqualStrings("0", c[0].original);
}

test "killed fixture: production catch candidate emitted, test body excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/error_path/killed.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "killed.zig", src);
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("0", c[0].original);
}

/// Parse + AstGen `source` in-process (exactly `zig ast-check`) and report
/// whether the compiler front-end accepts it. Unlike `Ast.parse` alone, this
/// catches semantic errors such as `unused capture` -- the failure mode of a
/// catch-with-capture mutant whose handler (but not the `|err|` capture) is
/// replaced by `unreachable`.
fn frontendAccepts(gpa: std.mem.Allocator, mutated: []const u8) !bool {
    const z = try gpa.dupeZ(u8, mutated);
    defer gpa.free(z);
    var tree = try std.zig.Ast.parse(gpa, z, .zig);
    defer tree.deinit(gpa);
    if (tree.errors.len != 0) return false; // parse-level errors
    var zir = try std.zig.AstGen.generate(gpa, tree);
    defer zir.deinit(gpa);
    return !zir.hasCompileErrors();
}

test "the applied error_catch_unreachable mutant compiles at a catch-with-capture site (M1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `catch |err| handler`: the `|err|` capture's scope is only the handler, so
    // replacing just the handler with `unreachable` orphans the capture ->
    // `catch |err| unreachable` -> `error: unused capture`, a guaranteed
    // compile_error that can never be killed. The span must cover the capture too,
    // producing the valid `catch unreachable` (M1).
    const src =
        \\pub fn f(e: anyerror!i32) i32 {
        \\    return e catch |err| handle(err);
        \\}
        \\fn handle(_: anyerror) i32 {
        \\    return -1;
        \\}
    ;
    var parsed = try ast_backend.parse(std.testing.allocator, "p.zig", src);
    defer parsed.deinit();
    const c = try collectErrorPath(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    // The span swallows the `|err|` capture, so the whole `|err| handle(err)` is
    // the original and the replacement `unreachable` yields `catch unreachable`.
    try expectEqualStrings("|err| handle(err)", c[0].original);
    try expectEqualStrings("unreachable", c[0].replacement);

    const mutated = try zentinel.sandbox.apply(a, src, c[0]);
    try expect(std.mem.indexOf(u8, mutated, "catch unreachable") != null);
    try expect(std.mem.indexOf(u8, mutated, "catch |err| unreachable") == null);
    // The produced mutant must actually pass the compiler front-end (no unused
    // capture); the prior test only inspected candidate fields, never compiled it.
    try expect(try frontendAccepts(a, mutated));
}
