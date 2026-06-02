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

    // Task 004: prove the minimal mutation fixture project compiles "through a
    // test command". Fixture project sources do not end in `_test.zig`, so the
    // recursive discovery above intentionally ignores them; they are compiled
    // and tested only through this explicit wiring. The no-eligible-sources
    // fixture (failure mode F-006) has no compilable entrypoint and is omitted.
    addFixtureCheck(b, test_step, "test/fixtures/projects/arithmetic_kill/calc.zig", target, optimize);

    // Task 111: real-binary integration test. Spawns the BUILT binary against a
    // committed fixture project so the real presentation-adapter I/O in
    // src/cli.zig (process execution, per-mutant workspace tree-copy, JSON report
    // writing) is exercised by `zig build test`, not only the mock-executor unit
    // tests. It is wired explicitly (and excluded from the recursive discovery
    // above) so it can receive the built binary's path.
    addIntegrationTest(b, test_step, zentinel_mod, exe, target, optimize);
}

// Wire the real-binary integration test: it imports a generated options module
// carrying the built binary's path (so it can spawn it) and the fixture project
// directory. `addOptionPath` also makes the test depend on the binary being built
// before it runs.
fn addIntegrationTest(
    b: *std.Build,
    test_step: *std.Build.Step,
    zentinel_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const opts = b.addOptions();
    opts.addOptionPath("zentinel_exe", exe.getEmittedBin());
    opts.addOption([]const u8, "fixture_dir", b.pathFromRoot("test/fixtures/integration/sample"));
    // The emitted-binary path is relative to the build root; pass the absolute
    // root so the test can resolve it regardless of the spawned child's cwd.
    opts.addOption([]const u8, "root_dir", b.pathFromRoot("."));

    const integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/integration_run_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zentinel", .module = zentinel_mod },
                .{ .name = "integration_options", .module = opts.createModule() },
            },
        }),
    });
    const run_integration = b.addRunArtifact(integration_test);
    test_step.dependOn(&run_integration.step);
}

// Compile and run a standalone fixture project source as a test so `zig build
// test` verifies it compiles. Fixture sources are std-only and do not import
// the zentinel module.
fn addFixtureCheck(
    b: *std.Build,
    test_step: *std.Build.Step,
    path: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const fixture_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_fixture_test = b.addRunArtifact(fixture_test);
    test_step.dependOn(&run_fixture_test.step);
}

fn addDiscoveredTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    zentinel_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const io = b.graph.io;
    // A missing/unreadable test/ must fail the build, not silently skip every unit
    // test -- `catch return` turned a wrong build root or partial checkout into a
    // green `zig build test` that ran zero discovered tests (S4). Consistent with the
    // walk-failure panics below.
    var test_dir = b.build_root.handle.openDir(io, "test", .{ .iterate = true }) catch
        @panic("test/ directory not found or unreadable -- zig build test cannot discover unit tests");
    defer test_dir.close(io);

    var paths_buf: [512][]const u8 = undefined;
    var count: usize = 0;
    var walker = test_dir.walk(b.allocator) catch @panic("failed to walk test/");
    defer walker.deinit();
    while (walker.next(io) catch @panic("failed to walk test/")) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, "_test.zig")) continue;
        // The real-binary integration test is wired explicitly (addIntegrationTest)
        // so it can receive the built binary's path; keep it out of generic discovery.
        if (std.mem.eql(u8, entry.basename, "integration_run_test.zig")) continue;
        if (count >= paths_buf.len) @panic("too many test/**/*_test.zig files");
        paths_buf[count] = b.dupe(entry.path);
        count += 1;
    }
    // Discovering zero unit tests means a wrong build root or a partial checkout, not
    // a passing suite; fail loudly rather than letting `zig build test` exit 0 having
    // run none of them (S4).
    if (count == 0) @panic("no test/**/*_test.zig files discovered -- check the build root / working directory");

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
