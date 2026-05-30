const std = @import("std");
const zentinel = @import("zentinel");

const lm = zentinel.list_mutants_command;
const config = zentinel.config;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const calc_src = "pub fn add(a: i32, b: i32) i32 {\n    return a + b;\n}\n";
const helper_src = "pub fn double(x: i32) i32 {\n    return x * 2;\n}\n";

const cfg_toml =
    \\[project]
    \\name = "sample"
    \\
    \\[mutators]
    \\enabled = ["arithmetic_add_sub", "arithmetic_mul_div"]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\
;

fn loadCfg(a: std.mem.Allocator, toml: []const u8) config.Config {
    var diag: config.Diagnostic = .{};
    return config.load(a, toml, &diag) catch @panic("config did not parse");
}

fn files() [2]lm.FileSource {
    return .{
        .{ .path = "src/calc.zig", .source = calc_src },
        .{ .path = "src/helper.zig", .source = helper_src },
    };
}

fn checkSnapshot(a: std.mem.Allocator, path: []const u8, actual: []const u8) !void {
    const io = std.testing.io;
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, a, std.Io.Limit.limited(1 << 20)) catch |err| switch (err) {
        error.FileNotFound => {
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = actual });
            return;
        },
        else => return err,
    };
    try expectEqualStrings(existing, actual);
}

test "generation is deterministic and never executes a command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fs = files();
    // generate() takes no executor and no commands: listing cannot run tests.
    const candidates = try lm.generate(a, loadCfg(a, cfg_toml), &fs, null);
    try expectEqual(@as(usize, 2), candidates.len);
    // Canonical order: src/calc.zig before src/helper.zig.
    try expectEqualStrings("src/calc.zig", candidates[0].file);
    try expectEqualStrings("arithmetic_add_sub", candidates[0].operator);
    try expectEqualStrings("src/helper.zig", candidates[1].file);
    try expectEqualStrings("arithmetic_mul_div", candidates[1].operator);

    // Re-running over identical input yields identical durable ids (determinism).
    const again = try lm.generate(a, loadCfg(a, cfg_toml), &fs, null);
    try expectEqualStrings(candidates[0].id, again[0].id);
    try expectEqualStrings(candidates[1].id, again[1].id);
}

test "operator filter narrows the listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fs = files();
    const filtered = try lm.generate(a, loadCfg(a, cfg_toml), &fs, "arithmetic_mul_div");
    try expectEqual(@as(usize, 1), filtered.len);
    try expectEqualStrings("arithmetic_mul_div", filtered[0].operator);
    try expectEqualStrings("src/helper.zig", filtered[0].file);
}

test "parseArgs reads documented options and rejects the rest" {
    const opts = try lm.parseArgs(&.{ "--operator", "arithmetic_add_sub", "--format", "json" });
    try expectEqualStrings("arithmetic_add_sub", opts.operator_filter.?);
    try expectEqual(lm.Format.json, opts.format);

    const defaults = try lm.parseArgs(&.{});
    try expect(defaults.operator_filter == null);
    try expectEqual(lm.Format.text, defaults.format);

    try expectError(error.UnknownOption, lm.parseArgs(&.{"--nope"}));
    try expectError(error.MissingValue, lm.parseArgs(&.{"--operator"}));
    try expectError(error.InvalidFormat, lm.parseArgs(&.{ "--format", "yaml" }));
}

test "snapshot: text listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fs = files();
    const candidates = try lm.generate(a, loadCfg(a, cfg_toml), &fs, null);
    const text = try lm.renderText(a, candidates);
    try checkSnapshot(a, "test/snapshots/list_mutants_basic.txt", text);
}

test "snapshot: json listing uses shared mutant fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fs = files();
    const candidates = try lm.generate(a, loadCfg(a, cfg_toml), &fs, null);
    const json = try lm.renderJson(a, candidates);
    try checkSnapshot(a, "test/snapshots/list_mutants_basic.json", json);
}
