const std = @import("std");

pub fn parseOr(s: []const u8) i32 {
    return std.fmt.parseInt(i32, s, 10) catch 0;
}

pub fn handled(s: []const u8) i32 {
    return std.fmt.parseInt(i32, s, 10) catch -1;
}

pub fn alreadyUnreachable(s: []const u8) i32 {
    return std.fmt.parseInt(i32, s, 10) catch unreachable;
}
