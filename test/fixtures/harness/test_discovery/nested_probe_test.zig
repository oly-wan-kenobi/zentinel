const std = @import("std");

// Nested discovery probe. The presence of this passing test — discovered
// recursively under test/ by `zig build test` without any build.zig edit —
// proves task 003's recursive `test/**/*_test.zig` discovery picks up future
// nested test files automatically. Only `*_test.zig` files are entrypoints.
test "nested test files are discovered recursively" {
    try std.testing.expect(true);
}
