// Layer: deterministic_core
//
// Markdown fenced-block parser for doctests (docs/DOCTEST_BLOCK_FORMATS.md).
// Line-oriented and deterministic: it scans fenced code blocks (3+ backticks,
// CommonMark-style nesting where a fence closes only on >= its own length),
// preserves file/line/raw-info/raw-content, classifies supported doctest blocks
// into typed metadata, and emits deterministic diagnostics for unsupported
// executable doctest tags and unterminated doctest fences. It does NOT group
// blocks into cases or execute anything.
const std = @import("std");
const block = @import("block.zig");
const error_codes = @import("../error_codes.zig");

pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    line: u32,
};

pub const Parsed = struct {
    blocks: []const block.Block,
    diagnostics: []const Diagnostic,
};

const Fence = struct { len: u8, close: bool };

/// Classify a line as a fence: number of leading backticks (after up to three
/// leading spaces) and whether it has no trailing info (a valid closing fence).
fn fenceOf(line: []const u8) Fence {
    var s = line;
    var sp: usize = 0;
    while (sp < s.len and sp < 3 and s[sp] == ' ') sp += 1;
    s = s[sp..];
    var n: usize = 0;
    while (n < s.len and s[n] == '`') n += 1;
    const rest = std.mem.trim(u8, s[n..], " \t\r");
    return .{ .len = @intCast(@min(n, 255)), .close = rest.len == 0 };
}

pub fn parse(arena: std.mem.Allocator, file: []const u8, source: []const u8) std.mem.Allocator.Error!Parsed {
    var blocks: std.ArrayList(block.Block) = .empty;
    var diags: std.ArrayList(Diagnostic) = .empty;

    var i: usize = 0;
    var line_no: u32 = 0;
    while (i < source.len) {
        const nl = std.mem.indexOfScalarPos(u8, source, i, '\n');
        const line = source[i..(nl orelse source.len)];
        const next = if (nl) |n| n + 1 else source.len;
        line_no += 1;

        const open = fenceOf(line);
        if (open.len < 3) {
            i = next;
            continue;
        }

        // Opening fence. Scan for the matching close (>= open length, no info).
        const open_line = line_no;
        const info = std.mem.trim(u8, line[backtickEnd(line)..], " \t\r");
        const content_start = next;
        var j = next;
        var jline = line_no;
        var content_end: usize = source.len;
        var after_close: usize = source.len;
        var close_line: u32 = 0;
        while (j < source.len) {
            const cnl = std.mem.indexOfScalarPos(u8, source, j, '\n');
            const cline = source[j..(cnl orelse source.len)];
            const cnext = if (cnl) |n| n + 1 else source.len;
            jline += 1;
            const cf = fenceOf(cline);
            if (cf.len >= open.len and cf.close) {
                content_end = j;
                after_close = cnext;
                close_line = jline;
                break;
            }
            j = cnext;
        }

        if (close_line == 0) {
            // Unterminated fence. Only an executable-looking doctest fence (a
            // doctest language at a doctest fence length) is a reported error.
            if (open.len <= 4 and block.languageFromToken(firstToken(info)) != .other) {
                try diags.append(arena, .{ .code = error_codes.doctest_invalid_block, .message = "unterminated doctest fence", .line = open_line });
            }
            break;
        }

        const b = try classify(arena, file, open_line, close_line, open.len, info, source[content_start..content_end], &diags);
        try blocks.append(arena, b);
        i = after_close;
        line_no = close_line;
    }

    return .{
        .blocks = try blocks.toOwnedSlice(arena),
        .diagnostics = try diags.toOwnedSlice(arena),
    };
}

fn backtickEnd(line: []const u8) usize {
    var sp: usize = 0;
    while (sp < line.len and sp < 3 and line[sp] == ' ') sp += 1;
    var n: usize = sp;
    while (n < line.len and line[n] == '`') n += 1;
    return n;
}

fn firstToken(info: []const u8) []const u8 {
    var it = std.mem.tokenizeAny(u8, info, " \t");
    return it.next() orelse "";
}

fn classify(
    arena: std.mem.Allocator,
    file: []const u8,
    line_start: u32,
    line_end: u32,
    fence_len: u8,
    info: []const u8,
    content: []const u8,
    diags: *std.ArrayList(Diagnostic),
) std.mem.Allocator.Error!block.Block {
    var b: block.Block = .{
        .file = file,
        .line_start = line_start,
        .line_end = line_end,
        .fence_len = fence_len,
        .info = info,
        .content = content,
        .language = .other,
        .kind = .none,
        .match_mode = .none,
        .case_label = null,
        .is_doctest = false,
    };

    // 5+ backtick fences are documentation-only until a future task extends the
    // parser (docs/DOCTEST_BLOCK_FORMATS.md).
    if (fence_len > 4) return b;

    var it = std.mem.tokenizeAny(u8, info, " \t");
    const lang_tok = it.next() orelse return b; // plain fence -> documentation-only
    b.language = block.languageFromToken(lang_tok);
    if (b.language == .other) return b; // non-doctest language -> documentation-only

    var unsupported = false;
    while (it.next()) |tok| {
        if (block.kindFromToken(tok)) |k| {
            b.kind = k;
        } else if (block.matchModeFromToken(tok)) |m| {
            b.match_mode = m;
        } else if (std.mem.startsWith(u8, tok, "case:")) {
            b.case_label = tok["case:".len..];
        } else if (std.mem.indexOfScalar(u8, tok, ':') != null) {
            // key:value metadata is accepted and preserved via the raw info string.
        } else {
            unsupported = true;
        }
    }

    if (unsupported) {
        try diags.append(arena, .{ .code = error_codes.doctest_unsupported_tag, .message = "unsupported executable doctest tag", .line = line_start });
        return b; // not a valid executable doctest
    }

    b.is_doctest = true;
    return b;
}
