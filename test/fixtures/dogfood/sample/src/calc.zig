const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn lte(a: i32, b: i32) bool {
    return a <= b;
}

test "calc operations" {
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
    try std.testing.expect(lte(2, 2));
}
