const std = @import("std");

// `noFail` never returns an error after acquiring `p`, so the errdefer cleanup
// never runs on the success path. Removing it (errdefer {}) is unobservable when
// no test forces the error path, so the errdefer_remove mutant SURVIVES.
pub fn noFail(alloc: std.mem.Allocator) !*i32 {
    const p = try alloc.create(i32);
    errdefer alloc.destroy(p);
    p.* = 1;
    return p;
}
