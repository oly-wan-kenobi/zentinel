const std = @import("std");

// The error path of `safeParse` is never exercised by any test (no invalid input
// is passed), so the error_catch_unreachable mutant (handler -> unreachable)
// SURVIVES: the catch branch never runs.
pub fn safeParse(s: []const u8) i32 {
    return std.fmt.parseInt(i32, s, 10) catch 0;
}
