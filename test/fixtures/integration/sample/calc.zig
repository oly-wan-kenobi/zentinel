//! Integration fixture (task 111). A real, std-only Zig source the shipped
//! binary mutates end-to-end. `add` is covered by a same-file test, so its
//! arithmetic mutant is killed; `mul` has no test, so its mutant survives. This
//! file is intentionally NOT named `*_test.zig` so build.zig's recursive test
//! discovery never sweeps it into zentinel's own suite.
const std = @import("std");

pub fn add(a: i64, b: i64) i64 {
    return a + b;
}

pub fn mul(a: i64, b: i64) i64 {
    return a * b;
}

test "add is covered so its mutant is killed" {
    try std.testing.expectEqual(@as(i64, 5), add(2, 3));
}
