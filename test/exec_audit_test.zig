const std = @import("std");
const zentinel = @import("zentinel");

const pm = zentinel.project_model;
const safety_modes = zentinel.safety_modes;
const sandbox = zentinel.sandbox;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

// --- M3: discover never descends into excluded dirs ------------------------

fn containsPath(files: []const []const u8, want: []const u8) bool {
    for (files) |f| {
        if (std.mem.eql(u8, f, want)) return true;
    }
    return false;
}

test "discover copies real sources but never descends into .zig-cache/zig-out/.git" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    // A project with real sources at the root and nested, plus eligible-looking
    // `.zig` files buried inside each excluded tree. `.zig-cache` in particular
    // holds a parallel run's transient per-mutant workspaces, so a walker that
    // descends there both wastes work and races sibling teardown.
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.writeFile(io, .{ .sub_path = "keep.zig", .data = "pub const x = 1;\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "src/nested.zig", .data = "pub const y = 2;\n" });
    try tmp.dir.createDirPath(io, ".zig-cache/zentinel/workspaces/run/m_other");
    try tmp.dir.writeFile(io, .{ .sub_path = ".zig-cache/zentinel/workspaces/run/m_other/sibling.zig", .data = "pub const z = 3;\n" });
    try tmp.dir.createDirPath(io, "zig-out/bin");
    try tmp.dir.writeFile(io, .{ .sub_path = "zig-out/bin/artifact.zig", .data = "pub const w = 4;\n" });
    try tmp.dir.createDirPath(io, ".git");
    try tmp.dir.writeFile(io, .{ .sub_path = ".git/hook.zig", .data = "pub const g = 5;\n" });
    // A sibling that only PREFIX-collides with `zig-out` must still be discovered,
    // proving the prune is by whole basename and not a raw byte prefix.
    try tmp.dir.createDirPath(io, "zig-outputs");
    try tmp.dir.writeFile(io, .{ .sub_path = "zig-outputs/foo.zig", .data = "pub const s = 6;\n" });

    var dir = try tmp.dir.openDir(io, ".", .{ .iterate = true });
    defer dir.close(io);

    // Include EVERYTHING and exclude nothing that touches the cache/build/VCS
    // dirs: the file-level `isEligible` backstop would happily include the buried
    // files if the walker descended, so their absence proves the directory prune.
    const include = [_][]const u8{"**/*.zig"};
    const exclude = [_][]const u8{};
    const files = try pm.discover(a, io, dir, &include, &exclude);

    // Real sources (including the prefix-colliding sibling) are discovered.
    try expect(containsPath(files, "keep.zig"));
    try expect(containsPath(files, "src/nested.zig"));
    try expect(containsPath(files, "zig-outputs/foo.zig"));
    // The excluded trees are never entered, so their eligible-looking files are
    // absent even though the (empty) exclude list would have permitted them.
    try expect(!containsPath(files, ".zig-cache/zentinel/workspaces/run/m_other/sibling.zig"));
    try expect(!containsPath(files, "zig-out/bin/artifact.zig"));
    try expect(!containsPath(files, ".git/hook.zig"));

    // Deterministic lexicographic order is preserved across the pruned walk.
    var i: usize = 1;
    while (i < files.len) : (i += 1) {
        try expect(!std.mem.lessThan(u8, files[i], files[i - 1]));
    }
}

// --- L2: argvForMode places -Doptimize BEFORE a `--` passthrough separator ---

fn indexOfArg(argv: []const []const u8, want: []const u8) ?usize {
    for (argv, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, want)) return i;
    }
    return null;
}

test "argvForMode inserts -Doptimize before the `--` separator for zig build" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // `zig build test -- --filter x`: everything after `--` is opaque passthrough
    // to the test binary, so an APPENDED `-Doptimize=...` would be ignored and the
    // verdict would silently run in Debug. The flag must land BEFORE `--`.
    const argv = [_][]const u8{ "zig", "build", "test", "--", "--filter", "x" };
    const out = try safety_modes.argvForMode(arena, &argv, .ReleaseFast);

    const flag_idx = indexOfArg(out, "-Doptimize=ReleaseFast") orelse return error.TestUnexpectedResult;
    const sep_idx = indexOfArg(out, "--") orelse return error.TestUnexpectedResult;
    // Decisive: the optimize flag is a real `zig build` argument (left of `--`),
    // not a passthrough token (right of `--`).
    try expect(flag_idx < sep_idx);

    // The passthrough region is preserved verbatim and in order after `--`.
    try expectEqual(@as(usize, 7), out.len);
    try expectEqualStrings("--filter", out[sep_idx + 1]);
    try expectEqualStrings("x", out[sep_idx + 2]);
    // The leading command tokens are untouched.
    try expectEqualStrings("zig", out[0]);
    try expectEqualStrings("build", out[1]);
    try expectEqualStrings("test", out[2]);
}

test "argvForMode still appends -Doptimize when zig build has no separator" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Absent any `--`, insert-before-separator degenerates to append, so the
    // no-passthrough path stays byte-for-byte as before.
    const argv = [_][]const u8{ "zig", "build", "test" };
    const out = try safety_modes.argvForMode(arena, &argv, .ReleaseSafe);
    try expectEqual(@as(usize, 4), out.len);
    try expectEqualStrings("-Doptimize=ReleaseSafe", out[3]);
}

// --- exec-runSpecs: sandbox.validate checks span/original without a copy ------

fn spanMutant(source_len: u64, byte_start: u64, byte_end: u64, original: []const u8, replacement: []const u8) mutant.Mutant {
    _ = source_len;
    return .{
        .id = "m_exec_audit",
        .backend = .ast,
        .backend_version = "0.16.0",
        .backend_stability = .stable,
        .operator = "test_op",
        .operator_stability = .stable,
        .file = "src/x.zig",
        .span = .{
            .byte_start = byte_start,
            .byte_end = byte_end,
            .line_start = 1,
            .column_start = 1,
            .line_end = 1,
            .column_end = 1,
        },
        .original = original,
        .replacement = replacement,
        .expected_compile = .compiles,
    };
}

test "sandbox.validate accepts an appliable patch and rejects span/original errors" {
    const source = "const a = 1;\n";

    // `1` at bytes [10,11) -> valid span whose source bytes equal `original`.
    const good = spanMutant(source.len, 10, 11, "1", "2");
    try sandbox.validate(source, good);

    // Span past the end of source.
    const oob = spanMutant(source.len, 10, source.len + 5, "1", "2");
    try expectError(error.SpanOutOfRange, sandbox.validate(source, oob));

    // Reversed span (start > end).
    const reversed = spanMutant(source.len, 11, 10, "1", "2");
    try expectError(error.SpanOutOfRange, sandbox.validate(source, reversed));

    // In-range span, but the source bytes there do not equal `original` ("9").
    const mismatch = spanMutant(source.len, 10, 11, "9", "2");
    try expectError(error.PatchMismatch, sandbox.validate(source, mismatch));
}

test "sandbox.validate agrees with apply on what is appliable" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const source = "const a = 1;\n";

    // validate() and apply() share one validation path: when validate succeeds,
    // apply produces the patched bytes; when validate fails, apply fails the same
    // way. This is what lets the mutant runner call the allocation-free validate()
    // instead of allocating and discarding apply()'s full patched buffer.
    const good = spanMutant(source.len, 10, 11, "1", "2");
    try sandbox.validate(source, good);
    const patched = try sandbox.apply(arena, source, good);
    try expectEqualStrings("const a = 2;\n", patched);

    const mismatch = spanMutant(source.len, 10, 11, "9", "2");
    try expectError(error.PatchMismatch, sandbox.validate(source, mismatch));
    try expectError(error.PatchMismatch, sandbox.apply(arena, source, mismatch));
}
