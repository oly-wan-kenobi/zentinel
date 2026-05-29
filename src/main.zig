// Layer: presentation_adapter
const std = @import("std");
const zentinel = @import("zentinel");

// Minimal bootstrap entry point. No CLI behavior exists yet; this only proves
// the executable target compiles and links against the root module.
pub fn main() void {
    std.debug.print("{s} {s}\n", .{ zentinel.project_name, zentinel.version });
}
