//! Minimal arithmetic fixture source. A same-file test fully exercises each
//! function so that future arithmetic mutants are expected to be killed. This
//! file is intentionally NOT named `*_test.zig`, so the recursive test
//! discovery in build.zig does not sweep it into the zentinel suite; it is
//! compiled and tested only through the explicit fixture-check wiring.
const std = @import("std");

pub fn add(a: i64, b: i64) i64 {
    return a + b;
}

pub fn sub(a: i64, b: i64) i64 {
    return a - b;
}

test "add and sub are exercised so arithmetic mutants are killed" {
    try std.testing.expectEqual(@as(i64, 5), add(2, 3));
    try std.testing.expectEqual(@as(i64, -1), sub(2, 3));
}
