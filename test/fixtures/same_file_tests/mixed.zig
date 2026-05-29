const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add works" {
    try std.testing.expectEqual(@as(i32, 3), add(1 + 0, 2));
}
