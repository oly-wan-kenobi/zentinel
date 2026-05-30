const std = @import("std");

pub fn withCleanup(alloc: std.mem.Allocator) !*i32 {
    const p = try alloc.create(i32);
    errdefer alloc.destroy(p);
    p.* = 1;
    return p;
}

pub fn alreadyEmpty(alloc: std.mem.Allocator) !*i32 {
    const p = try alloc.create(i32);
    errdefer {}
    p.* = 1;
    return p;
}
