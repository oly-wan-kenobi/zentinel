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
    const exe_path = if (std.fs.path.isAbsolute(options.zentinel_exe))
        options.zentinel_exe
    else
        try std.fs.path.join(a, &.{ options.root_dir, options.zentinel_exe });

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
