const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add is correct" {
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
}

test "add handles zero" {
    try std.testing.expectEqual(@as(i32, 1), add(1, 0));
}
