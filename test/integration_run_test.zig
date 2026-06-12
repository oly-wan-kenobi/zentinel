//! Real-binary end-to-end integration test.
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
    // them). `invalid` must be zero: previously the error_catch_unreachable
    // mutant's `original` borrowed the parsed tree's source and dangled past the
    // per-file `defer parsed.deinit()`. This is an END-TO-END smoke check that the
    // Collector.add() dup is wired through the real binary -- NOT the byte-level
    // teardown guard: the binary uses an ArenaAllocator whose `free` is a no-op
    // rewind that neither frees nor poisons `owned_source` (so no "0xAA" here).
    // The actual revert-catching guard is the GPA-backed teardown test in
    // test/sandbox_test.zig (F-1 plus the all-stable-operator case).
    try expectEqual(@as(i64, 3), summary.get("total").?.integer);
    try expectEqual(@as(i64, 1), summary.get("killed").?.integer);
    try expectEqual(@as(i64, 2), summary.get("survived").?.integer);
    try expectEqual(@as(i64, 0), summary.get("invalid").?.integer);

    // Bind the EXACT per-mutant kill/survive mapping, not just the fungible
    // aggregate counts: killed==1/survived==2 is invariant under an
    // add<->mul classification swap (add's mutant wrongly surviving while mul's is
    // wrongly killed leaves both totals unchanged), so only the per-mutant
    // (operator, span line, status) assertions below actually pin kill-detection
    // end-to-end. add's arithmetic_add_sub at calc.zig:13 (original `+`) is KILLED
    // by the same-file `add` test; mul's arithmetic_mul_div at calc.zig:17
    // (original `*`) SURVIVES (no test exercises it); parsePositive's
    // error_catch_unreachable at calc.zig:21 SURVIVES and its `original` is the
    // real handler text (`0`), not freed memory, never dropped to `invalid`
    // (regression coverage for the dangling-original fix).
    const mutants = parsed.object.get("mutants").?.array;
    var saw_add_sub = false;
    var saw_mul_div = false;
    var saw_error_catch = false;
    for (mutants.items) |entry| {
        const obj = entry.object;
        const operator = obj.get("operator").?.string;
        const status = obj.get("result").?.object.get("status").?.string;
        const line_start = obj.get("span").?.object.get("line_start").?.integer;
        if (std.mem.eql(u8, operator, "arithmetic_add_sub")) {
            saw_add_sub = true;
            try expectEqualStrings("calc.zig", obj.get("file").?.string);
            try expectEqual(@as(i64, 13), line_start);
            try expectEqualStrings("+", obj.get("original").?.string);
            try expectEqualStrings("killed", status);
        } else if (std.mem.eql(u8, operator, "arithmetic_mul_div")) {
            saw_mul_div = true;
            try expectEqualStrings("calc.zig", obj.get("file").?.string);
            try expectEqual(@as(i64, 17), line_start);
            try expectEqualStrings("*", obj.get("original").?.string);
            try expectEqualStrings("survived", status);
        } else if (std.mem.eql(u8, operator, "error_catch_unreachable")) {
            saw_error_catch = true;
            try expectEqual(@as(i64, 21), line_start);
            try expectEqualStrings("survived", status);
            try expectEqualStrings("0", obj.get("original").?.string);
        }
    }
    try expect(saw_add_sub);
    try expect(saw_mul_div);
    try expect(saw_error_catch);
}

test "zentinel init writes its config at zentinel.config_default_path, not a private duplicate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const exe_path = try exePath(a);
    // `init` in an empty project writes the starter config into the cwd root.
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "init" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => {
            std.debug.print("integration: binary did not exit normally; stderr:\n{s}\n", .{result.stderr});
            return error.BinaryCrashed;
        },
    }

    // The adapter must write the config to the SAME path the core resolves it
    // from by default -- the single source of truth `zentinel.config_default_path`
    // (root.zig) -- not a private duplicate literal in cli.zig. Locating the
    // written file through the exported constant is what binds `init`'s write path
    // to that source of truth: if cli.zig carried an unlinked copy and the core
    // constant were renamed, `init` would write somewhere the rest of the system
    // never looks, and this access would fail with FileNotFound.
    try tmp.dir.access(io, zentinel.config_default_path, .{});
}

test "a successful run leaves no per-run workspace dir under .zig-cache/zentinel/workspaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try copyFixtureFile(io, tmp.dir, "calc.zig", a);
    try copyFixtureFile(io, tmp.dir, "zentinel.toml", a);

    const exe_path = try exePath(a);
    const result = std.process.run(a, io, .{
        .argv = &.{ exe_path, "--config", "zentinel.toml", "run", "--report", "json" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    }) catch |err| {
        std.debug.print("integration: spawning {s} failed: {s}\n", .{ exe_path, @errorName(err) });
        return err;
    };
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => {
            std.debug.print("integration: binary did not exit normally; stderr:\n{s}\n", .{result.stderr});
            return error.BinaryCrashed;
        },
    }

    // setupWorkspace materialized .zig-cache/zentinel/workspaces/{run_id}/{m_id}
    // (via createDirPath) for each of the fixture's 3 mutants. mutantRunSpecsFn's
    // defer deleted each per-mutant leaf, but previously nothing removed the
    // {run_id} container, so every invocation leaked exactly one stale `run_<hex>`
    // dir under the controlled cache namespace. After a successful run the
    // workspaces dir must therefore contain NO `run_*` child.
    var ws = tmp.dir.openDir(io, ".zig-cache/zentinel/workspaces", .{ .iterate = true }) catch |err| switch (err) {
        // No workspaces dir at all also means nothing leaked.
        error.FileNotFound => return,
        else => return err,
    };
    defer ws.close(io);
    var it = ws.iterate();
    while (try it.next(io)) |entry| {
        if (std.mem.startsWith(u8, entry.name, "run_")) {
            std.debug.print("integration: leaked per-run workspace dir: {s}\n", .{entry.name});
            try expect(false);
        }
    }
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

test "cache.directory governs where cache.json is written, not report.output_dir" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj/src");
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/zentinel.toml", .data =
        \\[project]
        \\name = "cachedir"
        \\
        \\[mutators]
        \\enabled = ["arithmetic_add_sub"]
        \\
        \\[test]
        \\commands = ["zig test src/calc.zig"]
        \\
        \\[cache]
        \\directory = "zig-out/custom-cache"
        \\
    });
    try tmp.dir.writeFile(io, .{ .sub_path = "proj/src/calc.zig", .data =
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

    // cache.json lands under the configured cache.directory...
    const in_cache_dir = try tmpPath(a, tmp, "proj/zig-out/custom-cache/cache.json");
    try std.Io.Dir.cwd().access(io, in_cache_dir, .{});
    // ...and NOT in the default report output dir (zig-out/zentinel).
    const in_report_dir = try tmpPath(a, tmp, "proj/zig-out/zentinel/cache.json");
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, in_report_dir, .{}));
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

test "run --help prints the run usage block on stdout and exits 0 without a config" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    // An empty dir: per-command help must work before any config loading.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const exe_path = try exePath(a);
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "run", "--help" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
    try expect(std.mem.indexOf(u8, result.stdout, "Usage:\n  zentinel [global options] run [options]") != null);
    try expect(std.mem.indexOf(u8, result.stdout, "--fail-on-survivors") != null);
    try expect(std.mem.indexOf(u8, result.stdout, "--report <text|json|jsonl|junit>") != null);
    try expectEqual(@as(usize, 0), result.stderr.len);
}

test "a run emits per-mutant progress on stderr and keeps the stdout report intact" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try copyFixtureFile(io, tmp.dir, "calc.zig", a);
    try copyFixtureFile(io, tmp.dir, "zentinel.toml", a);

    const exe_path = try exePath(a);
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "--config", "zentinel.toml", "run", "--report", "json" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => {
            std.debug.print("integration: binary did not exit normally; stderr:\n{s}\n", .{result.stderr});
            return error.BinaryCrashed;
        },
    }

    // One progress line per fixture mutant, on stderr only, in completion order.
    try expect(std.mem.indexOf(u8, result.stderr, "[1/3] ") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "[2/3] ") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "[3/3] ") != null);
    // Specific outcomes, not counts: the killed add mutant's line carries its
    // status, operator, and file:line (calc.zig:13, see the fixture).
    try expect(std.mem.indexOf(u8, result.stderr, "killed arithmetic_add_sub calc.zig:13") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "survived arithmetic_mul_div calc.zig:17") != null);

    // stdout stays the pure JSON report: progress never leaks into it.
    try expect(std.mem.indexOf(u8, result.stdout, "[1/3]") == null);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
    try expectEqual(@as(i64, 3), parsed.object.get("summary").?.object.get("total").?.integer);
}

test "run --quiet suppresses the stderr progress lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try copyFixtureFile(io, tmp.dir, "calc.zig", a);
    try copyFixtureFile(io, tmp.dir, "zentinel.toml", a);

    const exe_path = try exePath(a);
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "--config", "zentinel.toml", "run", "--quiet", "--report", "json" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
    try expect(std.mem.indexOf(u8, result.stderr, "[1/3]") == null);
    // The report itself is unchanged by --quiet (json rendering is canonical).
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, result.stdout, .{});
    try expectEqual(@as(i64, 3), parsed.object.get("summary").?.object.get("total").?.integer);
}

test "init infers the project name from build.zig.zon" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data =
        \\.{
        \\    .name = .inferred_project,
        \\    .version = "0.0.1",
        \\    .fingerprint = 0x1234,
        \\}
        \\
    });

    const exe_path = try exePath(a);
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "init" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
    const toml = try tmp.dir.readFileAlloc(io, zentinel.config_default_path, a, read_limit);
    try expect(std.mem.indexOf(u8, toml, "name = \"inferred_project\"") != null);
    try expect(std.mem.indexOf(u8, toml, "name = \"example\"") == null);
}

test "init without build.zig.zon infers the project name from the cwd basename" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const exe_path = try exePath(a);
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "init" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
    // The cwd is the tmp dir, so the inferred name is its random basename
    // (base64-url alphabet: always TOML-embeddable).
    const expected = try std.fmt.allocPrint(a, "name = \"{s}\"", .{tmp.sub_path[0..]});
    const toml = try tmp.dir.readFileAlloc(io, zentinel.config_default_path, a, read_limit);
    try expect(std.mem.indexOf(u8, toml, expected) != null);
}

test "init --name overrides any inference in the written config" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data = ".{ .name = .ignored_zon_name }\n" });

    const exe_path = try exePath(a);
    const result = try std.process.run(a, io, .{
        .argv = &.{ exe_path, "init", "--name", "explicit_name" },
        .cwd = .{ .dir = tmp.dir },
        .stdout_limit = read_limit,
        .stderr_limit = read_limit,
    });
    switch (result.term) {
        .exited => |code| try expectEqual(@as(u8, 0), code),
        else => return error.BinaryCrashed,
    }
    const toml = try tmp.dir.readFileAlloc(io, zentinel.config_default_path, a, read_limit);
    try expect(std.mem.indexOf(u8, toml, "name = \"explicit_name\"") != null);
    try expect(std.mem.indexOf(u8, toml, "ignored_zon_name") == null);
}
