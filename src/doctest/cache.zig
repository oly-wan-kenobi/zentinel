// Layer: deterministic_core
//
// Doctest cache metadata builder (docs/DOCTEST_ARCHITECTURE.md "Caching
// Opportunities"). It computes a deterministic per-case cache key over the
// documented input tuple via src/cache.zig and serializes human-readable cache
// metadata. Pure: it performs no storage and, in this phase, never reuses a
// cached result (`metadata_only`), so a doctest report is identical whether or
// not the cache is enabled. Content hashes are used instead of timestamps.
const std = @import("std");
const cache = @import("../cache.zig");
const report = @import("../report.zig");
const block = @import("block.zig");
const parser = @import("parser.zig");
const extractor = @import("extractor.zig");
const case_mod = @import("case.zig");
const workspace = @import("workspace.zig");

pub const RunInputs = struct {
    zig_version: []const u8,
    config_hash: []const u8,
    /// Conservative default: compute keys without reusing results.
    mode: report.CacheMode = .metadata_only,
};

/// Parse + extract a doc, then build deterministic doctest cache metadata.
pub fn buildMetadataFromSource(
    arena: std.mem.Allocator,
    file: []const u8,
    source: []const u8,
    run: RunInputs,
) std.mem.Allocator.Error!cache.DoctestMetadata {
    const parsed = try parser.parse(arena, file, source);
    const extracted = try extractor.extract(arena, file, parsed.blocks, parsed.diagnostics);
    return buildMetadata(arena, file, parsed.blocks, extracted.cases, run);
}

/// Build cache metadata from already-extracted cases.
pub fn buildMetadata(
    arena: std.mem.Allocator,
    file: []const u8,
    blocks: []const block.Block,
    cases: []const case_mod.Case,
    run: RunInputs,
) std.mem.Allocator.Error!cache.DoctestMetadata {
    var keys: std.ArrayList(cache.DoctestCaseKey) = .empty;
    // Index blocks by start line ONCE so the per-case / per-expectation-ref block
    // lookups below are O(1), not an O(B) scan per ref -- O(C*(1+R)*B) overall.
    const block_index = try buildBlockIndex(arena, blocks);
    for (cases) |c| {
        const content_hash = try hashBlock(arena, block_index, c.anchor_line);
        const expectation_hash = try hashExpectations(arena, block_index, c);
        const key = try cache.computeDoctestKey(arena, .{
            .engine_version = workspace.engine_version,
            .doc_file = file,
            .line_start = c.line_start,
            .line_end = c.line_end,
            .block_content_hash = content_hash,
            .expectation_hash = expectation_hash,
            .zig_version = run.zig_version,
            .command_kind = c.kind.toString(),
            .config_hash = run.config_hash,
        });
        try keys.append(arena, .{ .case_id = c.id, .kind = c.kind.toString(), .key = key });
    }
    return .{
        .engine_version = workspace.engine_version,
        .enabled = run.mode != .disabled,
        .mode = run.mode,
        .case_keys = try keys.toOwnedSlice(arena),
    };
}

fn hashBlock(arena: std.mem.Allocator, index: std.AutoHashMap(u32, block.Block), line: u32) std.mem.Allocator.Error![]const u8 {
    if (index.get(line)) |b| return cache.sourceHash(arena, normalizeLineEndings(arena, b.content) catch b.content);
    return cache.sourceHash(arena, "");
}

/// Normalize `\r\n` and a bare `\r` to `\n` before hashing so a doctest checked
/// out with different line-ending settings (e.g. git `core.autocrlf` on Windows)
/// derives the same durable case id and content hash as on `\n`-only systems.
/// Allocation failures fall back to the raw bytes (the caller treats a hash
/// mismatch as a cache miss, never a correctness failure).
fn normalizeLineEndings(arena: std.mem.Allocator, content: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.mem.indexOfScalar(u8, content, '\r') == null) return content; // fast path: no CR
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        if (content[i] == '\r') {
            try out.append(arena, '\n');
            if (i + 1 < content.len and content[i + 1] == '\n') i += 1; // swallow the paired LF
        } else {
            try out.append(arena, content[i]);
        }
    }
    return out.toOwnedSlice(arena);
}

fn hashExpectations(arena: std.mem.Allocator, index: std.AutoHashMap(u32, block.Block), c: case_mod.Case) std.mem.Allocator.Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    if (c.block_refs.len > 1) {
        for (c.block_refs[1..]) |ref| {
            if (index.get(case_mod.lineOfRef(ref))) |b| {
                // Include the block's kind, match mode, and language -- not just
                // its content -- so two expectation blocks with identical text but
                // different semantics (e.g. `text output contains` vs
                // `text output regex`) derive distinct cache keys. Without these,
                // enabling result reuse could serve a stale verdict. The durable
                // CASE id already incorporates grouping metadata; this closes the
                // gap for the cache key specifically.
                try buf.appendSlice(arena, @tagName(b.kind));
                try buf.append(arena, 0);
                try buf.appendSlice(arena, @tagName(b.match_mode));
                try buf.append(arena, 0);
                try buf.appendSlice(arena, @tagName(b.language));
                try buf.append(arena, 0);
                try buf.appendSlice(arena, b.content);
                try buf.append(arena, 0);
            }
        }
    }
    return cache.sourceHash(arena, buf.items);
}

// Block/source refs are parsed via the shared `case.lineOfRef`; the previous
// hand-rolled `n = n*10 + d` accumulator (the last un-hardened of four copies)
// could overflow on an overlong numeric ref. See src/doctest/case.zig.

/// Test-only counter: how many times the per-document block index (line_start ->
/// Block) is built. Every block is indexed ONCE so each case's block lookups are
/// O(1) map gets, not O(B) scans per expectation ref -- a regression that rebuilt
/// per case (or scanned per ref) would push this above 1.
pub var block_index_builds: usize = 0;

/// Index blocks by their starting line. First occurrence wins, matching the prior
/// `findBlockByLine` linear scan's first-match semantics.
fn buildBlockIndex(arena: std.mem.Allocator, blocks: []const block.Block) std.mem.Allocator.Error!std.AutoHashMap(u32, block.Block) {
    block_index_builds += 1;
    var index = std.AutoHashMap(u32, block.Block).init(arena);
    for (blocks) |b| {
        const gop = try index.getOrPut(b.line_start);
        if (!gop.found_existing) gop.value_ptr.* = b;
    }
    return index;
}
