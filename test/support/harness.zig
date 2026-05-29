const std = @import("std");

/// Replace the absolute project root with "<project>" and backslashes with "/"
/// so snapshots are stable across machines.
pub fn normalizePath(arena: std.mem.Allocator, text: []const u8, abs_root: []const u8) ![]const u8 {
    const replaced = if (abs_root.len == 0)
        try arena.dupe(u8, text)
    else
        try replaceAll(arena, text, abs_root, "<project>");
    for (replaced) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return replaced;
}

/// Replace the integer value of `"duration_ms": N` with `<duration>` so report
/// snapshots are deterministic regardless of measured timings.
pub fn normalizeDurationMs(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    const key = "\"duration_ms\":";
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], key)) {
            try out.appendSlice(arena, key);
            i += key.len;
            while (i < text.len and text[i] == ' ') : (i += 1) try out.append(arena, ' ');
            var had_digit = false;
            while (i < text.len and text[i] >= '0' and text[i] <= '9') : (i += 1) had_digit = true;
            if (had_digit) try out.appendSlice(arena, "<duration>");
        } else {
            try out.append(arena, text[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(arena);
}

/// Snapshot assertion: actual must equal expected exactly. Callers normalize
/// volatile fields (absolute paths, durations) before comparing.
pub fn expectSnapshot(expected: []const u8, actual: []const u8) !void {
    return std.testing.expectEqualStrings(expected, actual);
}

/// Isolated temporary directory for tests. Each call returns a uniquely-named
/// directory under the gitignored .zig-cache/tmp tree. Call `.cleanup()` when done.
pub fn tempDir() std.testing.TmpDir {
    return std.testing.tmpDir(.{});
}

/// Join a fixture-relative path under test/fixtures with forward slashes.
pub fn fixturePath(arena: std.mem.Allocator, rel: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "test/fixtures/{s}", .{rel});
}

fn replaceAll(arena: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const size = std.mem.replacementSize(u8, haystack, needle, replacement);
    const out = try arena.alloc(u8, size);
    _ = std.mem.replace(u8, haystack, needle, replacement, out);
    return out;
}
