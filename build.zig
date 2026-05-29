const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The shared root module other modules and tests import as "zentinel".
    const zentinel_mod = b.addModule("zentinel", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zentinel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zentinel", .module = zentinel_mod }},
        }),
    });
    b.installArtifact(exe);

    // Deterministic recursive test discovery: every `test/**/*_test.zig` file is
    // run by `zig build test` without per-file build.zig edits. Discovery is
    // sorted so test wiring order is reproducible across machines. Only files
    // ending in `_test.zig` are test entrypoints; other fixture sources are
    // excluded by that suffix convention.
    const test_step = b.step("test", "Run all test/**/*_test.zig files");
    addDiscoveredTests(b, test_step, zentinel_mod, target, optimize);
}

fn addDiscoveredTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    zentinel_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const io = b.graph.io;
    var test_dir = b.build_root.handle.openDir(io, "test", .{ .iterate = true }) catch return;
    defer test_dir.close(io);

    var paths_buf: [512][]const u8 = undefined;
    var count: usize = 0;
    var walker = test_dir.walk(b.allocator) catch @panic("failed to walk test/");
    defer walker.deinit();
    while (walker.next(io) catch @panic("failed to walk test/")) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, "_test.zig")) continue;
        if (count >= paths_buf.len) @panic("too many test/**/*_test.zig files");
        paths_buf[count] = b.dupe(entry.path);
        count += 1;
    }

    std.mem.sort([]const u8, paths_buf[0..count], {}, struct {
        fn lessThan(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lessThan);

    for (paths_buf[0..count]) |name| {
        const path = b.fmt("test/{s}", .{name});
        const unit_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "zentinel", .module = zentinel_mod }},
            }),
        });
        const run_unit_test = b.addRunArtifact(unit_test);
        test_step.dependOn(&run_unit_test.step);
    }
}
