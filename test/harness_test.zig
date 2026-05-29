const std = @import("std");
const harness = @import("support/harness.zig");

test "normalizePath replaces the project root and backslashes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try harness.normalizePath(
        arena.allocator(),
        "/abs/proj/src\\main.zig under /abs/proj",
        "/abs/proj",
    );
    try std.testing.expectEqualStrings("<project>/src/main.zig under <project>", out);
}

test "normalizeDurationMs replaces measured timings deterministically" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const out = try harness.normalizeDurationMs(arena.allocator(), "{\"duration_ms\": 1234, \"n\": 7}");
    try std.testing.expectEqualStrings("{\"duration_ms\": <duration>, \"n\": 7}", out);
}

test "expectSnapshot passes for equal normalized text" {
    try harness.expectSnapshot("a/b/c", "a/b/c");
}

test "temp fixture directories are isolated" {
    var t1 = harness.tempDir();
    defer t1.cleanup();
    var t2 = harness.tempDir();
    defer t2.cleanup();
    try std.testing.expect(!std.mem.eql(u8, &t1.sub_path, &t2.sub_path));
}
