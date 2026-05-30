const std = @import("std");

pub fn safeParse(s: []const u8) i32 {
    return std.fmt.parseInt(i32, s, 10) catch 0;
}

test "error path is exercised" {
    // Invalid input takes the catch branch; mutating the handler to
    // `unreachable` would panic here, so the error_catch_unreachable mutant is
    // killed by this same-file test.
    try std.testing.expectEqual(@as(i32, 0), safeParse("not a number"));
}
