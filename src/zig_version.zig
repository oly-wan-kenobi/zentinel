// Layer: deterministic_core
//
// Zig version policy (docs/ZIG_VERSION_POLICY.md, ADR-0007). This is the single
// version-policy module: it owns the compiled-in pinned supported version and
// the pure classification of a discovered version. Discovery itself (running
// `zig version`) is a side effect performed by the presentation adapter, which
// passes the result in as `Discovery` data so this module stays pure and
// testable without invoking the real Zig binary.
const std = @import("std");

/// The one compiled-in supported Zig version for this zentinel release.
pub const supported_version = "0.16.0";

/// Result of attempting to discover the local Zig version. Produced by the
/// adapter; consumed by the pure classification below.
pub const Discovery = union(enum) {
    not_found,
    version: []const u8,
};

pub const Status = enum {
    supported,
    not_found,
    unsupported,
    malformed,
};

/// Public diagnostic codes for Zig version failures (docs/ERROR_CODES.md).
pub const Code = enum {
    none,
    not_found,
    unsupported,

    pub fn token(self: Code) []const u8 {
        return switch (self) {
            .none => "",
            .not_found => "ZNTL_ZIG_NOT_FOUND",
            .unsupported => "ZNTL_ZIG_UNSUPPORTED_VERSION",
        };
    }
};

pub const Version = struct {
    major: u16,
    minor: u16,
    patch: u16,
    /// True when the string carries a pre-release or build suffix (`-`/`+`),
    /// e.g. a nightly `0.16.0-dev.*`. Such builds are never the pinned release.
    pre: bool,
};

/// Parse `MAJOR.MINOR.PATCH` with an optional `-pre`/`+build` suffix. Returns
/// null for anything that is not three numeric components.
pub fn parseVersion(s: []const u8) ?Version {
    var core = s;
    var pre = false;
    if (std.mem.indexOfAny(u8, s, "-+")) |idx| {
        core = s[0..idx];
        pre = true;
    }
    var it = std.mem.splitScalar(u8, core, '.');
    const maj = it.next() orelse return null;
    const min = it.next() orelse return null;
    const pat = it.next() orelse return null;
    if (it.next() != null) return null;
    const major = std.fmt.parseInt(u16, maj, 10) catch return null;
    const minor = std.fmt.parseInt(u16, min, 10) catch return null;
    const patch = std.fmt.parseInt(u16, pat, 10) catch return null;
    return .{ .major = major, .minor = minor, .patch = patch, .pre = pre };
}

/// Classify a discovery result against the pinned supported version.
pub fn classify(discovery: Discovery) Status {
    switch (discovery) {
        .not_found => return .not_found,
        .version => |v| {
            const parsed = parseVersion(v) orelse return .malformed;
            if (parsed.major == 0 and parsed.minor == 16 and parsed.patch == 0 and !parsed.pre) return .supported;
            return .unsupported;
        },
    }
}

pub fn codeFor(status: Status) Code {
    return switch (status) {
        .supported => .none,
        .not_found => .not_found,
        .unsupported, .malformed => .unsupported,
    };
}

/// Human diagnostic naming the detected version and the required policy.
pub fn message(arena: std.mem.Allocator, status: Status, detected: []const u8) std.mem.Allocator.Error![]const u8 {
    return switch (status) {
        .supported => arena.dupe(u8, ""),
        .not_found => std.fmt.allocPrint(arena, "Zig executable not found; zentinel requires Zig {s}", .{supported_version}),
        .unsupported => std.fmt.allocPrint(arena, "unsupported Zig version {s}; zentinel requires Zig {s}", .{ detected, supported_version }),
        .malformed => std.fmt.allocPrint(arena, "could not parse Zig version '{s}'; zentinel requires Zig {s}", .{ detected, supported_version }),
    };
}

/// Rendered stderr status line for `zentinel version`: null when Zig is
/// supported (nothing extra to report), otherwise an `error[CODE]: message`
/// line. `zentinel version` stays exit 0 regardless; `zentinel check` treats
/// the same conditions as fatal.
pub fn statusLine(arena: std.mem.Allocator, discovery: Discovery) std.mem.Allocator.Error!?[]const u8 {
    const status = classify(discovery);
    if (status == .supported) return null;
    const detected = switch (discovery) {
        .version => |v| v,
        .not_found => "",
    };
    const msg = try message(arena, status, detected);
    return try std.fmt.allocPrint(arena, "error[{s}]: {s}", .{ codeFor(status).token(), msg });
}
