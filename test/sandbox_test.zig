const std = @import("std");
const zentinel = @import("zentinel");
const sandbox = zentinel.sandbox;
const mutant = zentinel.mutant;

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
