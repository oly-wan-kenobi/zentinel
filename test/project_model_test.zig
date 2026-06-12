const std = @import("std");
const zentinel = @import("zentinel");
const pm = zentinel.project_model;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "glob matching supports * within a segment and ** across segments" {
    try expect(pm.matchGlob("src/**/*.zig", "src/calc.zig"));
    try expect(pm.matchGlob("src/**/*.zig", "src/sub/deep.zig"));
    try expect(!pm.matchGlob("src/**/*.zig", "test/x.zig"));
    try expect(pm.matchGlob("*.zig", "a.zig"));
    try expect(!pm.matchGlob("*.zig", "a.txt"));
    try expect(pm.matchGlob("test/**", "test/x.zig"));
    try expect(pm.matchGlob("test/**", "test/sub/y.zig"));
    try expect(!pm.matchGlob("test/**", "src/x.zig"));
}

test "matchGlob matches a path deeper than the old 64-segment cap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // "src/" + 70×"d/" + "deep.zig" = 72 path segments, beyond the old fixed
    // [64][]const u8 split buffer. splitSegments overflowed -> null -> matchGlob
    // returned false, so discover silently dropped this includable .zig file from
    // the mutation set with no diagnostic (false coverage).
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(a, "src/");
    var i: usize = 0;
    while (i < 70) : (i += 1) try buf.appendSlice(a, "d/");
    try buf.appendSlice(a, "deep.zig");
    const deep = buf.items;

    // The include glob must match the deeply-nested file, and a shallow exclude
    // must still NOT match it -- proving real segment matching, not a blanket pass.
    try expect(pm.matchGlob("src/**/*.zig", deep));
    try expect(!pm.matchGlob("test/**", deep));
    const include = [_][]const u8{"src/**/*.zig"};
    const exclude = [_][]const u8{"test/**"};
    try expect(pm.isEligible(deep, &include, &exclude));
}

test "eligibility requires an include match and no exclude match" {
    const include = [_][]const u8{"src/**/*.zig"};
    const exclude = [_][]const u8{ "test/**", ".zig-cache/**" };
    try expect(pm.isEligible("src/calc.zig", &include, &exclude));
    try expect(pm.isEligible("src/sub/deep.zig", &include, &exclude));
    try expect(!pm.isEligible("test/x.zig", &include, &exclude)); // excluded
    try expect(!pm.isEligible("docs/readme.zig", &include, &exclude)); // not included
    try expect(!pm.isEligible(".zig-cache/x.zig", &include, &exclude)); // excluded
}

test "discovers eligible source files from globs over a fixture project, not a hardcoded list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var dir = try std.Io.Dir.cwd().openDir(std.testing.io, "test/fixtures/run_command/sample", .{ .iterate = true });
    defer dir.close(std.testing.io);

    const include = [_][]const u8{"src/**/*.zig"};
    const exclude = [_][]const u8{"test/**"};
    const files = try pm.discover(a, std.testing.io, dir, &include, &exclude);

    // src/ files are included and sorted; the test/ file is excluded.
    try expectEqual(@as(usize, 2), files.len);
    try expectEqualStrings("src/calc.zig", files[0]);
    try expectEqualStrings("src/helper.zig", files[1]);
}
