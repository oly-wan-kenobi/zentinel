//! Real-binary end-to-end integration test (task 111).
//!
//! Unlike the mock-executor unit tests, this spawns the actual built `zentinel`
//! binary against a committed fixture project, so the real presentation-adapter
//! I/O in src/cli.zig -- process execution (`std.process.run`), the per-mutant
//! workspace tree-copy (`setupWorkspace`), and JSON report writing -- is exercised
//! by `zig build test`. build.zig wires this test explicitly (it is excluded from
//! the recursive `*_test.zig` discovery) so it receives the built binary's path
//! and the fixture directory through the generated `integration_options` module.
const std = @import("std");
const zentinel = @import("zentinel");
const options = @import("integration_options");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const read_limit = std.Io.Limit.limited(1 << 20);

fn copyFixtureFile(io: std.Io, dst: std.Io.Dir, name: []const u8, a: std.mem.Allocator) !void {
    const src = try std.fmt.allocPrint(a, "{s}/{s}", .{ options.fixture_dir, name });
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, src, a, read_limit);
    try dst.writeFile(io, .{ .sub_path = name, .data = bytes });
}

fn exePath(a: std.mem.Allocator) ![]const u8 {
    return if (std.fs.path.isAbsolute(options.zentinel_exe))
        options.zentinel_exe
    else
        try std.fs.path.join(a, &.{ options.root_dir, options.zentinel_exe });
}

fn tmpPath(a: std.mem.Allocator, tmp: std.testing.TmpDir, suffix: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, ".zig-cache/tmp/{s}/{s}", .{ tmp.sub_path[0..], suffix });
}

fn absTmpPath(a: std.mem.Allocator, tmp: std.testing.TmpDir, suffix: []const u8) ![]const u8 {
    return std.fs.path.join(a, &.{ options.root_dir, try tmpPath(a, tmp, suffix) });
}

test "the built binary mutates a real fixture project and reports one killed and one surviving mutant" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    // Copy the committed fixture into an isolated, writable workspace so the real
    // binary discovers, patches, and tests it without touching the repository.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try copyFixtureFile(io, tmp.dir, "calc.zig", a);
    try copyFixtureFile(io, tmp.dir, "zentinel.toml", a);

    // The built-binary path is relative to the project root, but the child runs
    // with cwd = the fixture copy, so resolve it to an absolute argv[0] first.
    const exe_path = try exePath(a);

    // Spawn the actual built binary with the fixture copy as its project root.
    // This drives the real execProcess / setupWorkspace / report-writing adapters.
    const result = std.process.run(a, io, .{
        .argv = &.{ exe_path, "--config", "zentinel.toml", "run", "--report", "json" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    }) catch |err| {
        std.debug.print("integration: spawning {s} failed: {s}\n", .{ exe_path, @errorName(err) });
        return err;
    };

    // The run completes normally and stdout carries the canonical JSON report.
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => {
            std.debug.print("integration: binary did not exit normally; stderr:\n{s}\n", .{result.stderr});
            return error.BinaryCrashed;
        },
    }

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{}) catch |err| {
        std.debug.print("integration: report was not valid JSON ({s}); stdout:\n{s}\n", .{ @errorName(err), result.stdout });
        return err;
    };
    const summary = parsed.object.get("summary").?.object;
    const config_hash = parsed.object.get("run").?.object.get("config_hash").?.string;
    try expectEqual(@as(usize, "sha256:".len + 64), config_hash.len);
    try expect(std.mem.startsWith(u8, config_hash, "sha256:"));

    // The real run produced the fixture's two arithmetic mutants plus the
    // error-path mutant: add's is killed by the same-file test; mul's and
    // parsePositive's error_catch_unreachable mutant survive (no test exercises
    // them). `invalid` must be zero -- before task 117 the error_catch_unreachable
    // mutant's `original` borrowed the parsed tree's source, dangled past the
    // per-file `defer parsed.deinit()`, and the real binary misclassified this
    // valid candidate as `invalid` on a Debug build (the freed bytes poisoned to
    // 0xAA), hiding a real survivor behind a false "0 survivors" for that operator.
    try expectEqual(@as(i64, 3), summary.get("total").?.integer);
    try expectEqual(@as(i64, 1), summary.get("killed").?.integer);
    try expectEqual(@as(i64, 2), summary.get("survived").?.integer);
    try expectEqual(@as(i64, 0), summary.get("invalid").?.integer);

    // A non-arithmetic operator (error_catch_unreachable) is executed end-to-end
    // and classified `survived`, never dropped to `invalid`; its `original` is the
    // real handler text (`0`), not freed memory (task 117 acceptance criterion 4).
    const mutants = parsed.object.get("mutants").?.array;
    var saw_error_catch = false;
    for (mutants.items) |entry| {
        const obj = entry.object;
        if (std.mem.eql(u8, obj.get("operator").?.string, "error_catch_unreachable")) {
            saw_error_catch = true;
            try expectEqualStrings("survived", obj.get("result").?.object.get("status").?.string);
            try expectEqualStrings("0", obj.get("original").?.string);
        }
    }
    try expect(saw_error_catch);
}

test "project.root moves discovery and command execution into the configured root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj/pkg/src");
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/zentinel.toml", .data =
        \\[project]
        \\name = "nested"
        \\root = "pkg"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
        \\[test]
        \\commands = ["zig test src/calc.zig"]
        \\
    });
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/pkg/src/calc.zig", .data =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\
        \\test "add" {
        \\    try std.testing.expectEqual(@as(i32, 3), add(1, 2));
        \\}
        \\
        \\const std = @import("std");
        \\
    });

    const exe_path = try exePath(a);
    const root_abs = try absTmpPath(a, tmp, "proj");
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "--root", root_abs, "run", "--report", "json" },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });

    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
    try expectEqualStrings("completed", parsed.object.get("run").?.object.get("status").?.string);
    try expectEqual(@as(i64, 1), parsed.object.get("summary").?.object.get("total").?.integer);
    try expectEqualStrings("src/calc.zig", parsed.object.get("mutants").?.array.items[0].object.get("file").?.string);
}

test "project.root moves list-mutants discovery into the configured root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj/pkg/src");
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/zentinel.toml", .data =
        \\[project]
        \\name = "nested-list"
        \\root = "pkg"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
    });
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/pkg/src/calc.zig", .data =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\
    });

    const exe_path = try exePath(a);
    const root_abs = try absTmpPath(a, tmp, "proj");
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "--root", root_abs, "list-mutants", "--format", "json" },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });

    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
    try expectEqual(@as(i64, 1), parsed.object.get("total").?.integer);
    try expectEqualStrings("src/calc.zig", parsed.object.get("mutants").?.array.items[0].object.get("file").?.string);
}

test "project.root moves doctest mutation docs and command evidence into the configured root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj/pkg/docs");
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/zentinel.toml", .data =
        \\[project]
        \\name = "nested-doctest"
        \\root = "pkg"
        \\
    });
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/pkg/docs/killed.md", .data =
        \\# killed documentation mutant
        \\
        \\```zig test
        \\const std = @import("std");
        \\
        \\fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
        \\
        \\test "add is correct" {
        \\    try std.testing.expect(add(2, 3) == 5);
        \\}
        \\```
        \\
    });

    const exe_path = try exePath(a);
    const root_abs = try absTmpPath(a, tmp, "proj");
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "--root", root_abs, "doctest", "--mutate", "--file", "docs/killed.md" },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });

    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
    const first = parsed.object.get("cases").?.array.items[0].object;
    const command = first.get("mutation").?.object.get("runner_evidence").?.object.get("command").?.object;
    const original = command.get("original").?.string;
    try expect(std.mem.indexOf(u8, original, ".zig-cache/zentinel/doctest-mutate/") != null);
    try expect(std.mem.indexOf(u8, original, "src/doctest.zig") == null);
    try expectEqualStrings("docs/killed.md", first.get("file").?.string);
}

test "explicit doctest config failures are rejected before missing docs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj/docs");

    const exe_path = try exePath(a);
    const root_abs = try absTmpPath(a, tmp, "proj");
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "--root", root_abs, "--config", "missing.toml", "doctest", "--file", "docs/missing.md", "--format", "json" },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });

    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 2), code),
        else => return error.BinaryCrashed,
    }
    try expect(std.mem.indexOf(u8, result.stderr, "config not found") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "documentation file not found") == null);
}

test "explicit doctest AI invalid config is rejected instead of silently falling back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj/docs");
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/bad.toml", .data = "[ai]\nprovider = \"remote\"\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/docs/x.md", .data = "# x\n" });

    const exe_path = try exePath(a);
    const root_abs = try absTmpPath(a, tmp, "proj");
    const result = try std.process.run(a, io, .{
        .argv = &.{
            exe_path,
            "--root",
            root_abs,
            "--config",
            "bad.toml",
            "doctest",
            "suggest",
            "--file",
            "docs/x.md",
            "--ai-provider",
            "stub",
            "--format",
            "json",
        },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });

    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 2), code),
        else => return error.BinaryCrashed,
    }
    try expect(std.mem.indexOf(u8, result.stderr, "ZNTL_CONFIG_INVALID_VALUE") != null);
    try expectEqual(@as(usize, 0), result.stdout.len);
}

test "the built binary rejects explicit doctest AI config paths that escape root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj/docs");
    try tmp.dir.writeFile(io, .{ .sub_path = "outside.toml", .data = zentinel.default_config });
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/docs/x.md", .data = "# x\n" });

    const exe_path = try exePath(a);
    const root_abs = try absTmpPath(a, tmp, "proj");
    const result = try std.process.run(a, io, .{
        .argv = &.{
            exe_path,
            "--root",
            root_abs,
            "--config",
            "../outside.toml",
            "doctest",
            "suggest",
            "--file",
            "docs/x.md",
            "--ai-provider",
            "stub",
            "--format",
            "json",
        },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });

    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 2), code),
        else => return error.BinaryCrashed,
    }
    try expect(std.mem.indexOf(u8, result.stderr, "--config must stay within the project root") != null);
}

test "the built binary accepts a valid absolute root for config loading" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj");
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/zentinel.toml", .data = zentinel.default_config });

    const exe_path = try exePath(a);
    const root_abs = try absTmpPath(a, tmp, "proj");
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "--root", root_abs, "check" },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });

    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
}

test "the built binary rejects explicit config symlink escapes through the adapter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj");
    try tmp.dir.writeFile(io, .{ .sub_path = "outside.toml", .data = zentinel.default_config });
    try tmp.dir.symLink(io, "../outside.toml", "proj/link.toml", .{});

    const exe_path = try exePath(a);
    const root_rel = try tmpPath(a, tmp, "proj");
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "--root", root_rel, "--config", "link.toml", "check" },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });

    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 2), code),
        else => return error.BinaryCrashed,
    }
    try expect(std.mem.indexOf(u8, result.stderr, "--config must stay within the project root") != null);
}
