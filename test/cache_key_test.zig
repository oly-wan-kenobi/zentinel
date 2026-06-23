const std = @import("std");
const zentinel = @import("zentinel");

const cache = zentinel.cache;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn baseInputs() cache.KeyInputs {
    return .{
        .mutant_id = "m_8kjyy9kdjw9zngpb31q659cqmt",
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .zig_cache_namespace = "global:/home/u/.cache/zig",
        .backend = "ast",
        .backend_version = "ast.v1.zig-0.16.0",
        .operator = "arithmetic_add_sub",
        .source_hash = "0000000000000000000000000000000000000000000000000000000000000000",
        .project_hash = "sha256:project",
        .config_hash = "sha256:cfg",
        .test_command = "zig test src/calc.zig",
        .configured_command = "zig build test",
        .mode = "Debug",
        .environment = "minimal",
        .environment_hash = "sha256:environment",
    };
}

fn differs(a: std.mem.Allocator, base_key: []const u8, inputs: cache.KeyInputs) !void {
    const k = try cache.computeKey(a, inputs);
    try expect(!std.mem.eql(u8, base_key, k));
}

test "cache key is stable across repeated computation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const k1 = try cache.computeKey(a, baseInputs());
    const k2 = try cache.computeKey(a, baseInputs());
    try expectEqualStrings(k1, k2);
    try expect(k1.len == 64); // hex sha256
}

test "changing any documented deterministic input changes the key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base_key = try cache.computeKey(a, baseInputs());

    {
        var i = baseInputs();
        i.source_hash = "1111111111111111111111111111111111111111111111111111111111111111";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.config_hash = "sha256:other";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.project_hash = "sha256:other-project";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.zig_version = "0.17.0";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.mode = "ReleaseFast";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.test_command = "zig build test";
        try differs(a, base_key, i);
    }
    {
        // The configured suite is a distinct key dimension from the executed
        // (possibly narrowed) command: a narrowed survivor's verdict is reverified
        // against it, so it must affect the key.
        var i = baseInputs();
        i.configured_command = "zig build test -Dother";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.zig_cache_namespace = "global:/tmp/other-cache";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.zentinel_version = "0.1.0";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.operator = "arithmetic_mul_div";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.environment = "inherit";
        try differs(a, base_key, i);
    }
    {
        var i = baseInputs();
        i.environment_hash = "sha256:other-environment";
        try differs(a, base_key, i);
    }
}

test "backend_version changes the key independently of the display backend name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base_key = try cache.computeKey(a, baseInputs());

    // Same backend display name "ast", different backend_version.
    var i = baseInputs();
    i.backend_version = "ast.v1.zig-0.17.0";
    try expectEqualStrings("ast", i.backend);
    try differs(a, base_key, i);
}

test "sourceHash is deterministic and content-sensitive" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const h1 = try cache.sourceHash(a, "pub fn add() void {}");
    const h2 = try cache.sourceHash(a, "pub fn add() void {}");
    const h3 = try cache.sourceHash(a, "pub fn add() i32 {}");
    try expectEqualStrings(h1, h2);
    try expect(!std.mem.eql(u8, h1, h3));
    try expect(h1.len == 64);
}

test "metadata snapshot distinguishes result keys from build-cache metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const result_keys = [_]cache.ResultKey{.{ .mutant_id = "m_8kjyy9kdjw9zngpb31q659cqmt", .key = try cache.computeKey(a, baseInputs()) }};
    const md = cache.Metadata{
        .enabled = true,
        .mode = .metadata_only,
        .result_keys = &result_keys,
        .build_cache = .{ .namespace = "<zig-cache-namespace>", .isolated = true },
    };
    const json = try cache.toJson(a, md);

    const path = "test/snapshots/cache_metadata.json";
    // Fail on a missing snapshot rather than silently writing one and passing: a
    // self-regenerating fixture would let an encoding change (e.g. the v2
    // length-prefixed key) sail through green by rewriting its own expectation.
    // This matches the fail-on-missing convention of the sibling snapshot tests.
    const existing = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20)) catch |err| switch (err) {
        error.FileNotFound => return err,
        else => return err,
    };
    try expectEqualStrings(existing, json);
}
