// Layer: presentation_adapter
const std = @import("std");
const zentinel = @import("zentinel");

const config_path = "zentinel.toml";

/// Thin presentation adapter: resolves config existence, runs the pure
/// deterministic dispatch in the zentinel core, writes output, and performs the
/// init file write. All decision logic lives in `zentinel.dispatch`.
pub fn run(
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
        try dir.writeFile(io, .{ .sub_path = config_path, .data = zentinel.default_config });
    }

    return outcome.exit_code;
}
