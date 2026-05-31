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
    for (cases) |c| {
        const content_hash = try hashBlock(arena, blocks, c.anchor_line);
        const expectation_hash = try hashExpectations(arena, blocks, c);
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

fn hashBlock(arena: std.mem.Allocator, blocks: []const block.Block, line: u32) std.mem.Allocator.Error![]const u8 {
    if (findBlockByLine(blocks, line)) |b| return cache.sourceHash(arena, b.content);
    return cache.sourceHash(arena, "");
}

fn hashExpectations(arena: std.mem.Allocator, blocks: []const block.Block, c: case_mod.Case) std.mem.Allocator.Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    if (c.block_refs.len > 1) {
        for (c.block_refs[1..]) |ref| {
            if (findBlockByLine(blocks, lineOfRef(ref))) |b| {
                try buf.appendSlice(arena, b.content);
                try buf.append(arena, 0);
            }
        }
    }
    return cache.sourceHash(arena, buf.items);
}

fn findBlockByLine(blocks: []const block.Block, line: u32) ?block.Block {
    for (blocks) |b| {
        if (b.line_start == line) return b;
    }
    return null;
}

fn lineOfRef(ref: []const u8) u32 {
    const first = std.mem.indexOfScalar(u8, ref, ':') orelse return 0;
    var i = first + 1;
    var n: u32 = 0;
    while (i < ref.len and ref[i] >= '0' and ref[i] <= '9') : (i += 1) n = n * 10 + (ref[i] - '0');
    return n;
}
