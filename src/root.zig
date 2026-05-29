// Layer: deterministic_core
const std = @import("std");

/// Stable project name. Deterministic compile-time constant.
pub const project_name = "zentinel";

/// Initial project version. Deterministic compile-time constant.
pub const version = "0.0.0";

test "project name is the stable constant" {
    try std.testing.expectEqualStrings("zentinel", project_name);
}

test "version is non-empty" {
    try std.testing.expect(version.len > 0);
}
