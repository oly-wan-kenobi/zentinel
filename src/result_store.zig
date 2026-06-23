//! Adapter-side disk-backed result store enabling cross-run result reuse
//! (`run_command.ResultStore`). This is CLI-layer infrastructure -- the
//! deterministic core never touches the filesystem; it only consults the injected
//! store interface (I-022). Kept in its own module so the disk logic is unit
//! testable without spawning the binary.
//!
//! Content-addressed: each entry is `<dir_path>/<key>.json`, where `key` is the
//! 64-char lowercase SHA-256 hex from `cache.computeKey` (filename-safe). Reads
//! and writes are best-effort and never fail a run -- any I/O error is swallowed
//! (a read error => cache miss; a write error => not persisted). The core calls
//! `get`/`put` only from its serial read/write phases (never a worker thread), so
//! the store needs no synchronization.

const std = @import("std");
const run_command = @import("run_command.zig");

const read_limit = std.Io.Limit.limited(1 << 20);

/// Maximum number of entries retained before `prune` deletes the oldest. Each
/// entry is a small JSON verdict, so a few thousand bounds the namespace to a few
/// MB while comfortably covering a large project's mutant set across recent runs.
pub const max_entries: usize = 4096;

pub const DiskResultStore = struct {
    io: std.Io,
    root_dir: std.Io.Dir,
    /// Project-relative directory holding entry files, e.g. `<cache.directory>/results`.
    dir_path: []const u8,
    /// Allocator backing the bytes returned by `get`; must outlive the read.
    gpa: std.mem.Allocator,
    made_dir: bool = false,

    /// Erase into the core's injected store interface.
    pub fn store(self: *DiskResultStore) run_command.ResultStore {
        return .{ .ctx = self, .getFn = getTrampoline, .putFn = putTrampoline };
    }

    fn entryPath(self: *DiskResultStore, buf: []u8, key: []const u8) ?[]const u8 {
        return std.fmt.bufPrint(buf, "{s}/{s}.json", .{ self.dir_path, key }) catch null;
    }

    pub fn get(self: *DiskResultStore, key: []const u8) ?[]const u8 {
        var buf: [512]u8 = undefined;
        const path = self.entryPath(&buf, key) orelse return null;
        return self.root_dir.readFileAlloc(self.io, path, self.gpa, read_limit) catch null;
    }

    pub fn put(self: *DiskResultStore, key: []const u8, bytes: []const u8) void {
        // Create the results dir lazily on first write so an all-hit run (or one
        // that produces no cacheable verdict) touches no filesystem state.
        if (!self.made_dir) {
            self.root_dir.createDirPath(self.io, self.dir_path) catch return;
            self.made_dir = true;
        }
        var buf: [512]u8 = undefined;
        const path = self.entryPath(&buf, key) orelse return;
        self.root_dir.writeFile(self.io, .{ .sub_path = path, .data = bytes }) catch {};
    }

    fn getTrampoline(ctx: *anyopaque, key: []const u8) ?[]const u8 {
        const self: *DiskResultStore = @ptrCast(@alignCast(ctx));
        return self.get(key);
    }

    fn putTrampoline(ctx: *anyopaque, key: []const u8, bytes: []const u8) void {
        const self: *DiskResultStore = @ptrCast(@alignCast(ctx));
        self.put(key, bytes);
    }
};

/// Best-effort LRU bound on the disk store: when entries exceed `max`, delete the
/// oldest (by mtime) back down to `max`. Run once per invocation, AFTER the run
/// has persisted this run's entries, so a hot entry written this run is retained.
/// Fully catch-ignored: a prune failure must never affect the run. `gpa` is a
/// scratch allocator for the listing (caller owns its lifetime / reset).
pub fn prune(io: std.Io, root_dir: std.Io.Dir, dir_path: []const u8, gpa: std.mem.Allocator, max: usize) void {
    var d = root_dir.openDir(io, dir_path, .{ .iterate = true }) catch return;
    defer d.close(io);
    const Entry = struct { name: []const u8, mtime: i96 };
    var list: std.ArrayList(Entry) = .empty;
    var it = d.iterate();
    while (it.next(io) catch null) |e| {
        if (e.kind != .file) continue;
        // `e.name` slices the iterator buffer; dupe it before the next `next`.
        const name = gpa.dupe(u8, e.name) catch return;
        const st = d.statFile(io, name, .{}) catch continue;
        list.append(gpa, .{ .name = name, .mtime = st.mtime.nanoseconds }) catch return;
    }
    if (list.items.len <= max) return;
    const lessThan = struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            return a.mtime < b.mtime;
        }
    }.lt;
    std.mem.sort(Entry, list.items, {}, lessThan);
    const remove = list.items.len - max;
    for (list.items[0..remove]) |e| d.deleteFile(io, e.name) catch {};
}
