// Layer: presentation_adapter
const std = @import("std");
const zentinel = @import("zentinel");

const config_path = "zentinel.toml";
const read_limit = std.Io.Limit.limited(1 << 20);

/// Thin presentation adapter. Pure decision logic lives in the zentinel core:
/// `zentinel.route` decides how to handle argv, `zentinel.dispatch` owns the
/// frozen Phase 0 commands, and `zentinel.check_command`/`zentinel.zig_version`
/// own check and version-policy logic. The adapter performs the I/O the core
/// cannot: resolving config existence, reading config bytes, running
/// `zig version`, and writing output.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    args: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    switch (zentinel.route(args)) {
        .passthrough => return runPassthrough(gpa, io, dir, args, stdout, stderr),
        .version => {
            // stdout stays the policy-only version text; discovered Zig status
            // is environment information on stderr and never makes `version` fatal.
            try stdout.writeAll(zentinel.version_text);
            if (try zentinel.zig_version.statusLine(gpa, discoverZig(gpa, io))) |line| {
                try stderr.print("{s}\n", .{line});
            }
            return 0;
        },
        .check => |globals| {
            const resolved = try resolveConfigPath(gpa, globals);
            const result = try zentinel.check_command.run(gpa, .{
                .config_source = readConfig(gpa, io, dir, resolved),
                .config_path = resolved,
                .zig = discoverZig(gpa, io),
            });
            if (result.stdout.len > 0) try stdout.writeAll(result.stdout);
            if (result.code.len > 0) {
                try stderr.print("error[{s}]: {s}\n", .{ result.code, result.message });
            } else if (result.message.len > 0) {
                try stderr.print("{s}\n", .{result.message});
            }
            return result.exit_code;
        },
    }
}

/// Phase 0 commands (help/version-policy/init/unknown/not-implemented) plus the
/// invalid-option diagnostics owned by the frozen `dispatch`.
fn runPassthrough(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    args: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const config_exists = blk: {
        dir.access(io, config_path, .{}) catch break :blk false;
        break :blk true;
    };

    const outcome = zentinel.dispatch(args, config_exists);

    if (outcome.stdout.len > 0) try stdout.writeAll(outcome.stdout);

    if (outcome.error_code != .none) {
        try stderr.print("error[{s}]: {s}\n", .{ outcome.error_code.token(), outcome.detail });
    } else if (outcome.stderr.len > 0) {
        try stderr.writeAll(outcome.stderr);
    }

    if (outcome.write_config) {
        const text = try zentinel.initConfigText(gpa, outcome.init_test_command);
        try dir.writeFile(io, .{ .sub_path = config_path, .data = text });
    }

    return outcome.exit_code;
}

/// Resolve the config path: an explicit `--config` wins; otherwise the default
/// config name is looked up under `--root` (default `.`).
fn resolveConfigPath(gpa: std.mem.Allocator, globals: zentinel.Globals) ![]const u8 {
    if (globals.config_explicit) return globals.config_path;
    if (std.mem.eql(u8, globals.root, ".")) return globals.config_path;
    return std.fmt.allocPrint(gpa, "{s}/{s}", .{ globals.root, globals.config_path });
}

fn readConfig(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) ?[]const u8 {
    return dir.readFileAlloc(io, path, gpa, read_limit) catch null;
}

/// Run `zig version` and classify the result. Any failure to obtain a version
/// (executable missing, non-zero exit, empty output) is reported as not found.
fn discoverZig(gpa: std.mem.Allocator, io: std.Io) zentinel.zig_version.Discovery {
    const result = std.process.run(gpa, io, .{ .argv = &.{ "zig", "version" } }) catch return .not_found;
    switch (result.term) {
        .exited => |code| if (code != 0) return .not_found,
        else => return .not_found,
    }
    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) return .not_found;
    return .{ .version = trimmed };
}
