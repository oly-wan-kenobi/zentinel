// Layer: presentation_adapter
const std = @import("std");
const cli = @import("cli.zig");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const raw_args = try init.minimal.args.toSlice(arena);
    var arg_slices = try arena.alloc([]const u8, raw_args.len);
    for (raw_args, 0..) |arg, idx| arg_slices[idx] = arg;
    // Drop the program name; dispatch operates on the remaining argv.
    const cli_args: []const []const u8 = if (arg_slices.len > 1) arg_slices[1..] else arg_slices[0..0];

    // The parent environment is threaded into the CLI so the run command can
    // restrict each test command to the documented minimal allowlist;
    // it is the only portable source of the parent env under the Io model.
    const code = try cli.run(arena, io, std.Io.Dir.cwd(), cli_args, stdout, stderr, init.environ_map);

    try stdout.flush();
    try stderr.flush();
    return code;
}
