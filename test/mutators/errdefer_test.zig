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

fn collect(a: std.mem.Allocator, parsed: ast_backend.Parsed) ![]mutant.Mutant {
    const test_ranges = try ast_backend.testDeclRanges(parsed, a);
    var collector = ast_backend.Collector.init(a);
    try error_path.collect(&collector, parsed, "ops.zig", test_ranges);
    return collector.finish();
}

test "errdefer statement -> errdefer {} candidate, classified may_fail" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/errdefer/ops.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "ops.zig", src);
    defer parsed.deinit();
    const c = try collect(a, parsed);

    // withCleanup yields one candidate; alreadyEmpty (`errdefer {}`) is skipped.
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("errdefer_remove", c[0].operator);
    // The span includes the statement-terminating `;`, so applying `errdefer {}`
    // replaces the whole statement and cannot orphan a `;` into `errdefer {};` (H2).
    try expectEqualStrings("errdefer alloc.destroy(p);", c[0].original);
    try expectEqualStrings("errdefer {}", c[0].replacement);
    // Removing the cleanup can leave a variable used only there unused -> may_fail.
    try expectEqual(mutant.ExpectedCompile.may_fail, c[0].expected_compile);
    try expect(std.mem.startsWith(u8, c[0].id, "m_"));
    try expect(c[0].equivalent_risks.len > 0);
}

test "an existing errdefer {} is not mutated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "e.zig",
        \\pub fn f(alloc: std.mem.Allocator) !*i32 {
        \\    const p = try alloc.create(i32);
        \\    errdefer {}
        \\    p.* = 1;
        \\    return p;
        \\}
        \\const std = @import("std");
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "a non-canonically-spaced empty errdefer is not mutated (L6)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `errdefer  {}` (two spaces) and `errdefer{}` (no space) are ALREADY the
    // post-mutation `errdefer {}`; emitting a mutant only rewrites whitespace, a
    // pure no-op that Zig cannot distinguish -- a guaranteed-equivalent survivor.
    // The exact-string guard let these through; the whitespace-insensitive one
    // skips them (L6).
    inline for (.{
        "pub fn f(alloc: std.mem.Allocator) !*i32 {\n    const p = try alloc.create(i32);\n    errdefer  {}\n    p.* = 1;\n    return p;\n}\nconst std = @import(\"std\");",
        "pub fn f(alloc: std.mem.Allocator) !*i32 {\n    const p = try alloc.create(i32);\n    errdefer{}\n    p.* = 1;\n    return p;\n}\nconst std = @import(\"std\");",
    }) |src| {
        var parsed = try ast_backend.parse(std.testing.allocator, "e.zig", src);
        defer parsed.deinit();
        const c = try collect(a, parsed);
        try expectEqual(@as(usize, 0), c.len);
    }
}

test "a block-body errdefer is replaced wholesale with errdefer {}" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "b.zig",
        \\pub fn f(alloc: std.mem.Allocator) !*i32 {
        \\    const p = try alloc.create(i32);
        \\    errdefer alloc.destroy(p);
        \\    return p;
        \\}
        \\const std = @import("std");
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("errdefer_remove", c[0].operator);
    try expectEqualStrings("errdefer {}", c[0].replacement);
}

test "defer (not errdefer) is not changed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "d.zig",
        \\pub fn f() void {
        \\    defer g();
        \\}
        \\fn g() void {}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "errdefer inside a test body is excluded" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var parsed = try ast_backend.parse(std.testing.allocator, "t.zig",
        \\const std = @import("std");
        \\test "t" {
        \\    const p = try std.testing.allocator.create(i32);
        \\    errdefer std.testing.allocator.destroy(p);
        \\    std.testing.allocator.destroy(p);
        \\}
    );
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 0), c.len);
}

test "survivor fixture: success-only errdefer yields a candidate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const src = try readFixture(a, "test/fixtures/mutators/errdefer/survivor.zig");
    var parsed = try ast_backend.parse(std.testing.allocator, "survivor.zig", src);
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    try expectEqualStrings("errdefer_remove", c[0].operator);
    try expectEqualStrings("errdefer alloc.destroy(p);", c[0].original);
}

test "the applied errdefer_remove mutant is syntactically valid -- no dangling semicolon (H2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The dominant idiom: an expression/assignment-bodied errdefer terminated by
    // `;`. The mutator spans the errdefer node, whose last token is the body
    // expression -- NOT the statement-terminating `;`. Replacing only that span
    // with `errdefer {}` left the `;` orphaned -> `errdefer {};`, which fails to
    // parse ("expected statement, found ';'"), so every such mutant was a
    // guaranteed compile_error that can never be killed (H2).
    const src =
        \\pub fn f(alloc: std.mem.Allocator) !*i32 {
        \\    const p = try alloc.create(i32);
        \\    errdefer alloc.destroy(p);
        \\    p.* = 1;
        \\    return p;
        \\}
        \\const std = @import("std");
    ;
    var parsed = try ast_backend.parse(std.testing.allocator, "f.zig", src);
    defer parsed.deinit();
    const c = try collect(a, parsed);
    try expectEqual(@as(usize, 1), c.len);
    // The span swallows the terminating `;`, so the original IS the whole statement.
    try expectEqualStrings("errdefer alloc.destroy(p);", c[0].original);
    try expectEqualStrings("errdefer {}", c[0].replacement);

    // Apply the candidate and re-parse: the mutated statement must be exactly
    // `errdefer {}` (a complete statement), never `errdefer {};`.
    const mutated = try zentinel.sandbox.apply(a, src, c[0]);
    try expect(std.mem.indexOf(u8, mutated, "errdefer {};") == null);
    try expect(std.mem.indexOf(u8, mutated, "errdefer {}\n") != null);
    var reparsed = try ast_backend.parse(std.testing.allocator, "f.zig", mutated);
    defer reparsed.deinit();
    try expect(reparsed.ok()); // no parse errors -> the applied mutant is valid Zig
}
