//! Unit tests for the disk-backed result store (src/result_store.zig), the CLI
//! adapter that makes M1 cross-run result reuse real: round-trip get/put, a miss
//! on an absent key, lazy directory creation, reuse through the erased
//! `run_command.ResultStore` interface, and the best-effort LRU entry-count bound.
//! Real filesystem I/O via std.testing.tmpDir + std.testing.io.
const std = @import("std");
const zentinel = @import("zentinel");

const rstore = zentinel.result_store;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn countFiles(io: std.Io, dir: std.Io.Dir, sub: []const u8) usize {
    var d = dir.openDir(io, sub, .{ .iterate = true }) catch return 0;
    defer d.close(io);
    var n: usize = 0;
    var it = d.iterate();
    while (it.next(io) catch null) |e| {
        if (e.kind == .file) n += 1;
    }
    return n;
}

test "result store: put then get round-trips; absent key misses; dir is lazy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;

    var s = rstore.DiskResultStore{ .io = io, .root_dir = tmp.dir, .dir_path = "results", .gpa = a };

    // Absent key (and absent dir) is a miss, not an error, and creates nothing.
    try expect(s.get("missing") == null);
    try expectEqual(@as(usize, 0), countFiles(io, tmp.dir, "results"));

    const payload = "{\"status\":\"killed\"}";
    s.put("abc123", payload);
    const got = s.get("abc123") orelse return error.ExpectedHit;
    try expectEqualStrings(payload, got);

    // A different key is still a miss.
    try expect(s.get("def456") == null);
}

test "result store: reuse through the erased ResultStore interface" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;

    var s = rstore.DiskResultStore{ .io = io, .root_dir = tmp.dir, .dir_path = "results", .gpa = a };
    const iface = s.store();

    try expect(iface.get("k") == null);
    iface.put("k", "payload-bytes");
    const got = iface.get("k") orelse return error.ExpectedHit;
    try expectEqualStrings("payload-bytes", got);
}

test "result store: prune bounds the entry count and is a no-op under the cap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;

    var s = rstore.DiskResultStore{ .io = io, .root_dir = tmp.dir, .dir_path = "results", .gpa = a };

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var kb: [16]u8 = undefined;
        const key = std.fmt.bufPrint(&kb, "k{d}", .{i}) catch unreachable;
        s.put(key, "x");
    }
    try expectEqual(@as(usize, 5), countFiles(io, tmp.dir, "results"));

    // A cap at or above the count leaves every entry in place.
    rstore.prune(io, tmp.dir, "results", a, 10);
    try expectEqual(@as(usize, 5), countFiles(io, tmp.dir, "results"));

    // A cap below the count deletes down to exactly the cap.
    rstore.prune(io, tmp.dir, "results", a, 2);
    try expectEqual(@as(usize, 2), countFiles(io, tmp.dir, "results"));
}

test "result store: prune on a missing directory is a harmless no-op" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    rstore.prune(std.testing.io, tmp.dir, "does_not_exist", a, 4);
}
