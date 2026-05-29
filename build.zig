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

    // Deterministic top-level test discovery: every `test/*_test.zig` file is
    // run by `zig build test` without per-file build.zig edits. Discovery is
    // sorted so test wiring order is reproducible across machines.
    const test_step = b.step("test", "Run all top-level test/*_test.zig files");
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

    var names_buf: [256][]const u8 = undefined;
    var count: usize = 0;
    var it = test_dir.iterate();
    while (it.next(io) catch @panic("failed to iterate test/")) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, "_test.zig")) continue;
        if (count >= names_buf.len) @panic("too many test/*_test.zig files");
        names_buf[count] = b.dupe(entry.name);
        count += 1;
    }

    std.mem.sort([]const u8, names_buf[0..count], {}, struct {
        fn lessThan(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lessThan);

    for (names_buf[0..count]) |name| {
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
