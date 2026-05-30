// Phase 2 semantic dogfood fixture: each function exercises one stable Phase 2
// mutator so the dogfood pass covers the whole Zig-native semantic set.
const std = @import("std");

// error_catch_unreachable: `catch 0` -> `catch unreachable`.
pub fn parse(s: []const u8) i32 {
    return std.fmt.parseInt(i32, s, 10) catch 0;
}

// optional_orelse_unreachable: `orelse 0` -> `orelse unreachable`.
pub fn unwrap(x: ?i32) i32 {
    return x orelse 0;
}

// optional_null_check: `== null` -> `!= null`.
pub fn isNull(x: ?i32) bool {
    return x == null;
}

// integer_literal_boundary: `i < 10` -> `i < 11` / `i < 9`.
pub fn inBounds(i: usize) bool {
    return i < 10;
}

// loop_boundary: range end `0..10` and the `while (total < n)` boundary.
pub fn countTo(n: usize) usize {
    var total: usize = 0;
    for (0..10) |x| {
        total += x;
    }
    while (total < n) {
        total += 1;
    }
    return total;
}

// errdefer_remove: `errdefer alloc.destroy(p)` -> `errdefer {}`.
pub fn withCleanup(alloc: std.mem.Allocator) !*i32 {
    const p = try alloc.create(i32);
    errdefer alloc.destroy(p);
    p.* = 1;
    return p;
}
