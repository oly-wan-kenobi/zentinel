const std = @import("std");
const zentinel = @import("zentinel");
const cache = zentinel.cache;
const dcache = zentinel.doctest.cache;
const report = zentinel.report;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const metadata_snapshot = @embedFile("snapshots/doctest_cache_metadata.json");

const base_inputs = cache.DoctestKeyInputs{
    .engine_version = "0.1.0",
    .doc_file = "docs/CLI_SPEC.md",
    .line_start = 5,
    .line_end = 10,
    .block_content_hash = "1111",
    .expectation_hash = "2222",
    .zig_version = "0.16.0",
    .command_kind = "cli",
    .config_hash = "sha256:cfg",
};

fn expectDifferentKey(a: std.mem.Allocator, base: []const u8, v: cache.DoctestKeyInputs) !void {
    const k = try cache.computeDoctestKey(a, v);
    try expect(!std.mem.eql(u8, base, k));
}

test "doctest cache key is deterministic across repeated runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const k1 = try cache.computeDoctestKey(a, base_inputs);
    const k2 = try cache.computeDoctestKey(a, base_inputs);
    try expectEqualStrings(k1, k2);
    try expectEqual(@as(usize, 64), k1.len); // hex sha256
}

test "doctest cache key changes when any documented input changes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try cache.computeDoctestKey(a, base_inputs);

    var v = base_inputs;
    v.engine_version = "0.2.0";
    try expectDifferentKey(a, base, v);
    v = base_inputs;
    v.doc_file = "docs/CONFIG_SPEC.md";
    try expectDifferentKey(a, base, v);
    v = base_inputs;
    v.line_start = 6;
    try expectDifferentKey(a, base, v);
    v = base_inputs;
    v.line_end = 11;
    try expectDifferentKey(a, base, v);
    v = base_inputs;
    v.block_content_hash = "9999";
    try expectDifferentKey(a, base, v);
    v = base_inputs;
    v.expectation_hash = "8888";
    try expectDifferentKey(a, base, v);
    v = base_inputs;
    v.zig_version = "0.17.0";
    try expectDifferentKey(a, base, v);
    v = base_inputs;
    v.command_kind = "zig_test";
    try expectDifferentKey(a, base, v);
    v = base_inputs;
    v.config_hash = "sha256:other";
    try expectDifferentKey(a, base, v);
}

test "cached results cannot be reused across Zig or doctest engine versions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try cache.computeDoctestKey(a, base_inputs);
    var zig_bump = base_inputs;
    zig_bump.zig_version = "0.16.1";
    var engine_bump = base_inputs;
    engine_bump.engine_version = "0.2.0";
    try expect(!std.mem.eql(u8, base, try cache.computeDoctestKey(a, zig_bump)));
    try expect(!std.mem.eql(u8, base, try cache.computeDoctestKey(a, engine_bump)));
}

test "doctest cache metadata snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = "test/fixtures/doctest/extraction/cases.md";
    const src = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
    const md = try dcache.buildMetadataFromSource(a, path, src, .{ .zig_version = "0.16.0", .config_hash = "sha256:deadbeef" });
    const json = try cache.doctestMetadataToJson(a, md);
    try expectEqualStrings(metadata_snapshot, json);
}

test "doctest cache is metadata-only and does not change extracted cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = "test/fixtures/doctest/extraction/cases.md";
    const src = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
    const md = try dcache.buildMetadataFromSource(a, path, src, .{ .zig_version = "0.16.0", .config_hash = "sha256:deadbeef" });
    // Conservative: keys are computed but reuse is disabled, so no cache hit can
    // ever change a doctest report.
    try expectEqual(report.CacheMode.metadata_only, md.mode);
    try expect(md.case_keys.len == 4); // cli, config, zig_test, mutation
    // One stable key per case.
    for (md.case_keys) |ck| {
        try expectEqual(@as(usize, 64), ck.key.len);
        try expect(std.mem.startsWith(u8, ck.case_id, "dt_"));
    }
}

test "the doctest block index is built once per document, not once per case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = "test/fixtures/doctest/extraction/cases.md";
    const src = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));

    // The fixture has 4 doctest cases; the block index must be built ONCE for the
    // whole document so each case's block lookup is an O(1) map get rather than a
    // fresh O(B) scan per expectation ref (the old O(C*(1+R)*B) behavior).
    dcache.block_index_builds = 0;
    const md = try dcache.buildMetadataFromSource(a, path, src, .{ .zig_version = "0.16.0", .config_hash = "sha256:deadbeef" });
    try expect(md.case_keys.len == 4);
    try expectEqual(@as(usize, 1), dcache.block_index_builds);
}

test "property: cache metadata is deterministic across repeated builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = "test/fixtures/doctest/extraction/cases.md";
    const src = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
    const j1 = try cache.doctestMetadataToJson(a, try dcache.buildMetadataFromSource(a, path, src, .{ .zig_version = "0.16.0", .config_hash = "sha256:deadbeef" }));
    const j2 = try cache.doctestMetadataToJson(a, try dcache.buildMetadataFromSource(a, path, src, .{ .zig_version = "0.16.0", .config_hash = "sha256:deadbeef" }));
    try expectEqualStrings(j1, j2);
}

test "property: distinct input tuples produce distinct keys (collision resistance)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var seen: std.ArrayList([]const u8) = .empty;
    const kinds = [_][]const u8{ "cli", "zig_test", "config", "config_fail", "mutation" };
    for (kinds) |k| {
        var line: u32 = 1;
        while (line <= 5) : (line += 1) {
            var v = base_inputs;
            v.command_kind = k;
            v.line_start = line;
            const key = try cache.computeDoctestKey(a, v);
            for (seen.items) |s| try expect(!std.mem.eql(u8, s, key));
            try seen.append(a, key);
        }
    }
}
