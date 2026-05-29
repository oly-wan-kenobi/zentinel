const std = @import("std");
const zentinel = @import("zentinel");

// The presence of this passing test, run by `zig build test`, proves that the
// build's top-level test discovery includes a second `test/*_test.zig` file
// without a per-file `build.zig` edit. Tasks 001 and 002 rely on this.
test "a second top-level test file is discovered and executed by zig build test" {
    try std.testing.expect(zentinel.project_name.len > 0);
}
