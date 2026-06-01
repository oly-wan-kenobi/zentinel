const std = @import("std");
const zentinel = @import("zentinel");
const zig_version = zentinel.zig_version;
const harness = @import("support/harness.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const unsupported_snapshot = @embedFile("snapshots/zig_unsupported.txt");

test "pinned supported version classifies as supported" {
    try expectEqualStrings("0.16.0", zig_version.supported_version);
    try expectEqual(zig_version.Status.supported, zig_version.classify(.{ .version = "0.16.0" }));
}

test "older and newer stable versions are unsupported" {
    try expectEqual(zig_version.Status.unsupported, zig_version.classify(.{ .version = "0.15.1" }));
    try expectEqual(zig_version.Status.unsupported, zig_version.classify(.{ .version = "0.17.0" }));
    try expectEqual(zig_version.Status.unsupported, zig_version.classify(.{ .version = "1.0.0" }));
}

test "nightly/dev builds of the pinned version are unsupported" {
    try expectEqual(zig_version.Status.unsupported, zig_version.classify(.{ .version = "0.16.0-dev.123+abcdef" }));
}

test "malformed version strings are malformed" {
    try expectEqual(zig_version.Status.malformed, zig_version.classify(.{ .version = "not-a-version" }));
    try expectEqual(zig_version.Status.malformed, zig_version.classify(.{ .version = "0.16" }));
    try expectEqual(zig_version.Status.malformed, zig_version.classify(.{ .version = "" }));
}

test "missing Zig executable classifies as not_found" {
    try expectEqual(zig_version.Status.not_found, zig_version.classify(.not_found));
}

test "status codes map to the public ZNTL tokens" {
    try expectEqualStrings("ZNTL_ZIG_NOT_FOUND", zig_version.codeFor(.not_found).token());
    try expectEqualStrings("ZNTL_ZIG_UNSUPPORTED_VERSION", zig_version.codeFor(.unsupported).token());
    try expectEqualStrings("ZNTL_ZIG_UNSUPPORTED_VERSION", zig_version.codeFor(.malformed).token());
}

test "unsupported diagnostic names detected and required versions (snapshot)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const msg = try zig_version.message(a, .unsupported, "0.15.1");
    const produced = try std.fmt.allocPrint(a, "{s}\n", .{msg});
    try harness.expectSnapshot(unsupported_snapshot, produced);
    try expect(std.mem.indexOf(u8, msg, "0.15.1") != null);
    try expect(std.mem.indexOf(u8, msg, "0.16.0") != null);
}

test "version-command Zig status is silent when supported and coded otherwise" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Supported Zig: `zentinel version` reports nothing extra on stderr.
    try expect((try zig_version.statusLine(a, .{ .version = "0.16.0" })) == null);

    // Missing Zig: reported but non-fatal for `version` (the caller still exits 0).
    const missing = (try zig_version.statusLine(a, .not_found)).?;
    try expect(std.mem.indexOf(u8, missing, "ZNTL_ZIG_NOT_FOUND") != null);

    // Unsupported Zig: reported with detected and required versions.
    const unsupported = (try zig_version.statusLine(a, .{ .version = "0.15.1" })).?;
    try expect(std.mem.indexOf(u8, unsupported, "ZNTL_ZIG_UNSUPPORTED_VERSION") != null);
    try expect(std.mem.indexOf(u8, unsupported, "0.15.1") != null);
}

test "execution paths use a fatal Zig diagnostic and never synthesize the pinned label" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try expectEqualStrings("0.16.0", (zig_version.supportedLabel(.{ .version = "0.16.0" })).?);
    try expect(zig_version.supportedLabel(.not_found) == null);
    try expect(zig_version.supportedLabel(.{ .version = "0.15.1" }) == null);

    const missing = try zig_version.fatalStatusLine(a, .not_found);
    try expect(std.mem.indexOf(u8, missing, "ZNTL_ZIG_NOT_FOUND") != null);
    try expectEqual(@as(u8, 2), zig_version.failureExit(.not_found));

    const supported = try zig_version.fatalStatusLine(a, .{ .version = "0.16.0" });
    try expectEqualStrings("", supported);
    try expectEqual(@as(u8, 0), zig_version.failureExit(.{ .version = "0.16.0" }));
}
