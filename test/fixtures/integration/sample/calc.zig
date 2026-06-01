//! Integration fixture (task 111). A real, std-only Zig source the shipped
//! binary mutates end-to-end. `add` is covered by a same-file test, so its
//! arithmetic mutant is killed; `mul` has no test, so its mutant survives.
//! `parsePositive` is covered only on its success path (task 117), so the
//! `error_catch_unreachable` mutant on its untested error path survives -- a
//! real survivor that the F-1 dangling-`original` defect would have hidden by
//! misclassifying it `invalid`. This file is intentionally NOT named
//! `*_test.zig` so build.zig's recursive test discovery never sweeps it into
//! zentinel's own suite.
const std = @import("std");

pub fn add(a: i64, b: i64) i64 {
    return a + b;
}

pub fn mul(a: i64, b: i64) i64 {
    return a * b;
}

pub fn parsePositive(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch 0;
}

test "add is covered so its mutant is killed" {
    try std.testing.expectEqual(@as(i64, 5), add(2, 3));
}

test "parsePositive succeeds but its error path is never exercised" {
    // Only the success path is tested, so `catch 0` -> `catch unreachable`
    // compiles and never trips: the error_catch_unreachable mutant survives.
    try std.testing.expectEqual(@as(i64, 42), parsePositive("42"));
}
