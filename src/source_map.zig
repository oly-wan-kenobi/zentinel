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
