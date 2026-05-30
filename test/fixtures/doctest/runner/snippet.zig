const std = @import("std");

test "doctest fixture snippet" {
    try std.testing.expect(1 + 1 == 2);
}
