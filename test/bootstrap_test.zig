const std = @import("std");
const zentinel = @import("zentinel");

test "root module exposes the stable project name" {
    try std.testing.expectEqualStrings("zentinel", zentinel.project_name);
}

test "root module exposes a non-empty initial version" {
    try std.testing.expect(zentinel.version.len > 0);
}
