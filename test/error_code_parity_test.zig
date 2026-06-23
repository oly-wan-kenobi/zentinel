// Error-code registry parity (M5): the stable `ZNTL_…` tokens emitted in `src/`
// and the rows in `docs/ERROR_CODES.md` are a two-way public contract, and they
// silently drift apart as new emission sites land. This test pins both directions
// so a missing row (or a stale documented code) fails CI instead of shipping:
//
//   1. every complete `ZNTL_<AREA>_<NAME>` literal emitted under `src/` has a row
//      in docs/ERROR_CODES.md;
//   2. every documented code that is not marked _(reserved …)_ is emitted by some
//      `src/` file.
//
// cwd is the project root during `zig build test` (as in zir_backend_test.zig's
// src/ sweep), so the source tree and the doc are read with project-relative paths.
const std = @import("std");

const expect = std.testing.expect;

/// A `ZNTL_` token is a *complete* error code when it is `ZNTL_` + at least two
/// underscore-separated uppercase/digit segments and does not end in `_`. Prose
/// references to a code *family* (`ZNTL_AI_*`, `ZNTL_DOCTEST_*`) tokenize to a
/// trailing-underscore fragment (`ZNTL_AI_`, `ZNTL_DOCTEST_`) once the `*` ends
/// the run; excluding trailing-underscore tokens drops those fragments while
/// keeping real codes (which never end in `_`).
fn isCompleteCode(tok: []const u8) bool {
    if (!std.mem.startsWith(u8, tok, "ZNTL_")) return false;
    if (tok[tok.len - 1] == '_') return false;
    // Need an AREA and a NAME: at least two '_' (ZNTL _ AREA _ NAME).
    var underscores: usize = 0;
    for (tok) |c| {
        if (c == '_') underscores += 1;
    }
    return underscores >= 2;
}

fn isCodeByte(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

/// Put every maximal `ZNTL_[A-Z0-9_]+` run in `text` that is a complete code into
/// `set` (keys are arena-owned copies, deduplicated by the map).
fn collectCodes(arena: std.mem.Allocator, set: *std.StringHashMap(void), text: []const u8) std.mem.Allocator.Error!void {
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], "ZNTL_")) {
            var end = i + 5;
            while (end < text.len and isCodeByte(text[end])) end += 1;
            const tok = text[i..end];
            if (isCompleteCode(tok) and !set.contains(tok)) {
                try set.put(try arena.dupe(u8, tok), {});
            }
            i = end;
        } else {
            i += 1;
        }
    }
}

/// Walk `src/` and collect every complete code literal emitted in a `.zig` file.
fn emittedCodes(arena: std.mem.Allocator) !std.StringHashMap(void) {
    const io = std.testing.io;
    var set = std.StringHashMap(void).init(arena);
    var src_dir = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer src_dir.close(io);
    var walker = try src_dir.walk(arena);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        const source = try src_dir.readFileAlloc(io, entry.path, arena, std.Io.Limit.limited(1 << 20));
        try collectCodes(arena, &set, source);
    }
    return set;
}

const DocCode = struct {
    code: []const u8,
    reserved: bool,
};

/// Parse the documented codes from docs/ERROR_CODES.md table rows. A code is read
/// from a backtick-wrapped token in a row (`| `ZNTL_…` | … |`); the row is
/// "reserved" when it carries the `reserved` marker word.
fn documentedCodes(arena: std.mem.Allocator) ![]DocCode {
    const io = std.testing.io;
    const md = try std.Io.Dir.cwd().readFileAlloc(io, "docs/ERROR_CODES.md", arena, std.Io.Limit.limited(1 << 20));
    var list: std.ArrayList(DocCode) = .empty;
    var lines = std.mem.splitScalar(u8, md, '\n');
    while (lines.next()) |line| {
        // Only table rows carry codes; a row begins with `|`.
        const trimmed = std.mem.trimStart(u8, line, " ");
        if (!std.mem.startsWith(u8, trimmed, "|")) continue;
        const tick = std.mem.indexOfScalar(u8, trimmed, '`') orelse continue;
        var end = tick + 1;
        while (end < trimmed.len and trimmed[end] != '`') end += 1;
        if (end >= trimmed.len) continue;
        const code = trimmed[tick + 1 .. end];
        if (!std.mem.startsWith(u8, code, "ZNTL_")) continue;
        const reserved = std.mem.indexOf(u8, line, "reserved") != null;
        try list.append(arena, .{ .code = code, .reserved = reserved });
    }
    return list.toOwnedSlice(arena);
}

fn docContains(docs: []const DocCode, code: []const u8) bool {
    for (docs) |d| {
        if (std.mem.eql(u8, d.code, code)) return true;
    }
    return false;
}

test "every emitted ZNTL_ code has a documented row in docs/ERROR_CODES.md" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var emitted = try emittedCodes(arena);
    const docs = try documentedCodes(arena);

    // Sanity: the sweep actually saw the tree and the doc actually parsed.
    try expect(emitted.count() > 10);
    try expect(docs.len > 10);

    var missing: usize = 0;
    var it = emitted.iterator();
    while (it.next()) |kv| {
        const code = kv.key_ptr.*;
        if (!docContains(docs, code)) {
            std.debug.print("emitted but undocumented error code: {s}\n", .{code});
            missing += 1;
        }
    }
    try expect(missing == 0);
}

test "every non-reserved documented code is emitted somewhere in src/" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var emitted = try emittedCodes(arena);
    const docs = try documentedCodes(arena);

    var unemitted: usize = 0;
    for (docs) |d| {
        if (d.reserved) continue;
        if (!emitted.contains(d.code)) {
            std.debug.print("documented (non-reserved) but unemitted error code: {s}\n", .{d.code});
            unemitted += 1;
        }
    }
    try expect(unemitted == 0);
}

test "the five diff/source/zir/doctest codes M5 added are documented" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const docs = try documentedCodes(arena);
    for ([_][]const u8{
        "ZNTL_DIFF_SCOPE_FAILED",
        "ZNTL_DIFF_SCOPE_EMPTY",
        "ZNTL_SOURCE_READ_FAILED",
        "ZNTL_ZIR_UNSUPPORTED",
        "ZNTL_DOCTEST_WORKSPACE_FAILED",
    }) |code| {
        try expect(docContains(docs, code));
    }
}

test "prefix-family fragments are not treated as complete codes" {
    // `ZNTL_AI_` / `ZNTL_DOCTEST_` are how a code *family* tokenizes from prose
    // like `ZNTL_AI_*`; they must be ignored so the parity check does not demand a
    // bogus row for them. A real code (no trailing `_`) is kept.
    try expect(!isCompleteCode("ZNTL_AI_"));
    try expect(!isCompleteCode("ZNTL_DOCTEST_"));
    try expect(!isCompleteCode("ZNTL_")); // bare prefix
    try expect(!isCompleteCode("ZNTL_CLI")); // only one segment, no NAME
    try expect(isCompleteCode("ZNTL_DIFF_SCOPE_FAILED"));
    try expect(isCompleteCode("ZNTL_AI_DISABLED"));
}
