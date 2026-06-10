// Layer: deterministic_core
//
// Pure byte <-> line/column mapping over a source buffer (docs/AST_BACKEND.md
// Source Mapping Strategy). Byte offsets are authoritative; line and column are
// 1-based for humans. Independent of the parser so mapping stays testable and
// deterministic. Columns count bytes, which round-trips exactly for ASCII/UTF-8
// byte offsets used for patching.
const std = @import("std");

pub const Position = struct {
    line: u32,
    column: u32,
};

/// Map a byte offset to a 1-based line/column. Returns null when the offset is
/// past the end of the source (the EOF offset == source.len is valid).
pub fn locate(source: []const u8, byte_offset: usize) ?Position {
    if (byte_offset > source.len) return null;
    var line: u32 = 1;
    var column: u32 = 1;
    var i: usize = 0;
    while (i < byte_offset) : (i += 1) {
        if (source[i] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{ .line = line, .column = column };
}

/// A precomputed newline index over one source buffer, so repeated `locate`
/// queries are O(log lines) instead of O(byte_offset). Building it once per file
/// turns a mutator's per-candidate, scan-from-zero mapping (O(sites * file_size),
/// i.e. quadratic) into O(file_size + sites * log lines). `init` allocates an
/// ascending array of the byte offset of every `\n`; `locate` binary-searches it.
/// `locate` is byte-for-byte equivalent to the free `locate` above (a property
/// test pins this), so it is a drop-in replacement on the candidate hot path.
pub const LineIndex = struct {
    /// Ascending byte offsets at which a `\n` occurs.
    newlines: []const usize,
    source_len: usize,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!LineIndex {
        var nl: std.ArrayList(usize) = .empty;
        for (source, 0..) |c, i| {
            if (c == '\n') try nl.append(allocator, i);
        }
        return .{ .newlines = try nl.toOwnedSlice(allocator), .source_len = source.len };
    }

    /// Count of newline offsets strictly less than `value` (= the 0-based number
    /// of line breaks before `value`).
    fn newlinesBefore(self: LineIndex, value: usize) usize {
        var lo: usize = 0;
        var hi: usize = self.newlines.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.newlines[mid] < value) lo = mid + 1 else hi = mid;
        }
        return lo;
    }

    pub fn locate(self: LineIndex, byte_offset: usize) ?Position {
        if (byte_offset > self.source_len) return null;
        const before = self.newlinesBefore(byte_offset);
        const line_start: usize = if (before == 0) 0 else self.newlines[before - 1] + 1;
        return .{
            .line = @intCast(before + 1),
            .column = @intCast(byte_offset - line_start + 1),
        };
    }
};

/// Map a 1-based line/column back to a byte offset. Returns null when the line
/// or column is zero, the line is past the end of the source, or the column is
/// past the end of that line.
pub fn byteOf(source: []const u8, pos: Position) ?usize {
    if (pos.line == 0 or pos.column == 0) return null;
    var line: u32 = 1;
    var i: usize = 0;
    while (line < pos.line) {
        if (i >= source.len) return null;
        if (source[i] == '\n') line += 1;
        i += 1;
    }
    var column: u32 = 1;
    while (column < pos.column) : (column += 1) {
        if (i >= source.len) return null;
        if (source[i] == '\n') return null;
        i += 1;
    }
    return i;
}
