// Layer: deterministic_core
//
// Pure, idempotent normalization of volatile doctest output before snapshot
// matching (docs/DOCTEST_ARCHITECTURE.md "Snapshot Strategy"). It rewrites
// absolute project paths, OS temp directories, generated workspace hashes,
// run ids, ISO timestamps, durations, ANSI color, and line endings to stable
// placeholders, and strips trailing whitespace per line while preserving line
// order. Re-normalizing already-normalized text is a no-op.
const std = @import("std");

pub const Options = struct {
    /// Absolute project root replaced with `<project>`; ignored when empty.
    project_root: []const u8 = "",
};

const Match = struct { len: usize, repl: []const u8 };

/// Walk `s` and replace every span matched by `matchFn` with its replacement.
fn transform(arena: std.mem.Allocator, s: []const u8, matchFn: *const fn (s: []const u8, i: usize) ?Match) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        if (matchFn(s, i)) |m| {
            try out.appendSlice(arena, m.repl);
            i += m.len;
        } else {
            try out.append(arena, s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(arena);
}

pub fn normalize(arena: std.mem.Allocator, input: []const u8, opts: Options) std.mem.Allocator.Error![]const u8 {
    var s = try transform(arena, input, matchLineEnding);
    s = try transform(arena, s, matchAnsi);
    if (opts.project_root.len > 0) s = try replaceAll(arena, s, opts.project_root, "<project>");
    s = try transform(arena, s, matchTempDir);
    s = try transform(arena, s, matchWorkspace);
    s = try transform(arena, s, matchRunId);
    s = try transform(arena, s, matchTimestamp);
    s = try transform(arena, s, matchDuration);
    s = try stripTrailingWhitespace(arena, s);
    return s;
}

fn replaceAll(arena: std.mem.Allocator, s: []const u8, needle: []const u8, repl: []const u8) std.mem.Allocator.Error![]const u8 {
    if (needle.len == 0) return s;
    const size = std.mem.replacementSize(u8, s, needle, repl);
    const out = try arena.alloc(u8, size);
    _ = std.mem.replace(u8, s, needle, repl, out);
    return out;
}

fn matchLineEnding(s: []const u8, i: usize) ?Match {
    if (s[i] == '\r') {
        if (i + 1 < s.len and s[i + 1] == '\n') return .{ .len = 2, .repl = "\n" };
        return .{ .len = 1, .repl = "\n" };
    }
    return null;
}

fn matchAnsi(s: []const u8, i: usize) ?Match {
    // CSI sequence: ESC '[' ... final byte in '@'..'~'.
    if (s[i] != 0x1b or i + 1 >= s.len or s[i + 1] != '[') return null;
    var j = i + 2;
    while (j < s.len) : (j += 1) {
        if (s[j] >= '@' and s[j] <= '~') return .{ .len = j - i + 1, .repl = "" };
    }
    return null;
}

fn isPathChar(c: u8) bool {
    return switch (c) {
        // `:` is excluded so a temp-dir match stops before a trailing
        // `:line:column` compiler-diagnostic reference (e.g.
        // `/var/folders/.../foo.zig:5:9: error`). Previously `:` was treated as
        // a path char, so the whole `...foo.zig:5:9:` was collapsed to `<tmp>`,
        // destroying the line/column info diagnostic matching needs. The temp-dir
        // prefixes are Unix-only (no drive-letter `:`), so excluding `:` is safe.
        ' ', '\t', '\n', '\r', '"', '\'', '`', ')', ']', '}', ',', ';', ':' => false,
        else => true,
    };
}

fn matchTempDir(s: []const u8, i: usize) ?Match {
    const prefixes = [_][]const u8{ "/private/var/folders/", "/var/folders/", "/tmp/" };
    for (prefixes) |p| {
        if (std.mem.startsWith(u8, s[i..], p)) {
            var j = i + p.len;
            while (j < s.len and isPathChar(s[j])) j += 1;
            return .{ .len = j - i, .repl = "<tmp>" };
        }
    }
    return null;
}

fn isBase32(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn matchWorkspace(s: []const u8, i: usize) ?Match {
    const prefix = ".zig-cache/zentinel/doctest/";
    if (!std.mem.startsWith(u8, s[i..], prefix)) return null;
    var j = i + prefix.len;
    const start = j;
    while (j < s.len and isBase32(s[j])) j += 1;
    if (j == start) return null;
    return .{ .len = j - i, .repl = ".zig-cache/zentinel/doctest/<workspace>" };
}

fn matchRunId(s: []const u8, i: usize) ?Match {
    const prefix = "doctest_run_";
    if (!std.mem.startsWith(u8, s[i..], prefix)) return null;
    var j = i + prefix.len;
    const start = j;
    while (j < s.len and isBase32(s[j])) j += 1;
    if (j == start) return null;
    return .{ .len = j - i, .repl = "doctest_run_<id>" };
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn matchTimestamp(s: []const u8, i: usize) ?Match {
    // YYYY-MM-DDTHH:MM:SS with optional fractional seconds and zone.
    if (i + 19 > s.len) return null;
    const t = s[i..];
    if (!(isDigit(t[0]) and isDigit(t[1]) and isDigit(t[2]) and isDigit(t[3]) and
        t[4] == '-' and isDigit(t[5]) and isDigit(t[6]) and t[7] == '-' and
        isDigit(t[8]) and isDigit(t[9]) and t[10] == 'T' and
        isDigit(t[11]) and isDigit(t[12]) and t[13] == ':' and
        isDigit(t[14]) and isDigit(t[15]) and t[16] == ':' and
        isDigit(t[17]) and isDigit(t[18]))) return null;
    var j: usize = 19;
    if (j < t.len and t[j] == '.') {
        j += 1;
        while (j < t.len and isDigit(t[j])) j += 1;
    }
    if (j < t.len and t[j] == 'Z') {
        j += 1;
    } else if (j < t.len and (t[j] == '+' or t[j] == '-')) {
        var k = j + 1;
        while (k < t.len and (isDigit(t[k]) or t[k] == ':')) k += 1;
        j = k;
    }
    return .{ .len = j, .repl = "<timestamp>" };
}

fn matchDuration(s: []const u8, i: usize) ?Match {
    // A number (optionally fractional) immediately followed by a time unit, at a
    // non-alphanumeric left boundary and a non-letter right boundary.
    if (i > 0 and (isBase32(s[i - 1]) or s[i - 1] == '_')) return null;
    if (!isDigit(s[i])) return null;
    var j = i;
    while (j < s.len and isDigit(s[j])) j += 1;
    if (j < s.len and s[j] == '.') {
        j += 1;
        while (j < s.len and isDigit(s[j])) j += 1;
    }
    const units = [_][]const u8{ "ms", "us", "ns", "s" };
    for (units) |u| {
        if (std.mem.startsWith(u8, s[j..], u)) {
            const after = j + u.len;
            if (after < s.len and ((s[after] >= 'a' and s[after] <= 'z') or (s[after] >= 'A' and s[after] <= 'Z'))) continue;
            return .{ .len = after - i, .repl = "<duration>" };
        }
    }
    return null;
}

fn stripTrailingWhitespace(arena: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var it = std.mem.splitScalar(u8, s, '\n');
    var first = true;
    while (it.next()) |line| {
        if (!first) try out.append(arena, '\n');
        first = false;
        const trimmed = std.mem.trimEnd(u8, line, " \t");
        try out.appendSlice(arena, trimmed);
    }
    return out.toOwnedSlice(arena);
}
