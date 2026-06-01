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
        error.FileNotFound => return err,
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

test "operator filtering happens before physical-edit dedupe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cfg =
        \\[project]
        \\name = "loop-only"
        \\
        \\[mutators]
        \\enabled = ["loop_boundary"]
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
    ;
    const fs = [_]lm.FileSource{.{
        .path = "src/loop.zig",
        .source =
        \\pub fn count(n: usize) usize {
        \\    var i: usize = 0;
        \\    while (i < n) : (i += 1) {}
        \\    return i;
        \\}
        ,
    }};

    const candidates = try lm.generate(a, loadCfg(a, cfg), &fs, null);
    try expectEqual(@as(usize, 1), candidates.len);
    try expectEqualStrings("loop_boundary", candidates[0].operator);
    try expectEqualStrings("<", candidates[0].original);
    try expectEqualStrings("<=", candidates[0].replacement);
}

test "list-mutants reports parse failures instead of silently dropping a source file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fs = [_]lm.FileSource{.{ .path = "src/broken.zig", .source = "pub fn broken(\n" }};
    try expectError(error.BackendParseError, lm.generate(a, loadCfg(a, cfg_toml), &fs, null));
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

// --- Phase-2 operator wiring (task 109) ------------------------------------
//
// The optional/error_path/integer_boundary/loop_boundary collectors are
// implemented but were never called by the generators, so enabling their (stable)
// operators silently produced zero mutants on code that contains their target
// constructs. These fixtures already drive each collector in its own unit test.
const optional_ops = @embedFile("fixtures/mutators/optional/ops.zig");
const error_ops = @embedFile("fixtures/mutators/error_path/ops.zig");
const errdefer_ops = @embedFile("fixtures/mutators/errdefer/ops.zig");
const integer_ops = @embedFile("fixtures/mutators/integer_boundary/ops.zig");
const loop_ops = @embedFile("fixtures/mutators/loop_boundary/ops.zig");

const phase2_cfg =
    \\[project]
    \\name = "phase2"
    \\
    \\[mutators]
    \\enabled = ["optional_orelse_unreachable", "optional_null_check", "error_catch_unreachable", "errdefer_remove", "integer_literal_boundary", "loop_boundary"]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\
;

fn hasOperator(candidates: []const zentinel.mutant.Mutant, op: []const u8) bool {
    for (candidates) |m| {
        if (std.mem.eql(u8, m.operator, op)) return true;
    }
    return false;
}

test "list-mutants wires the Phase-2 collectors so each stable Phase-2 operator emits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fs = [_]lm.FileSource{
        .{ .path = "src/opt.zig", .source = optional_ops },
        .{ .path = "src/err.zig", .source = error_ops },
        .{ .path = "src/errd.zig", .source = errdefer_ops },
        .{ .path = "src/int.zig", .source = integer_ops },
        .{ .path = "src/loop.zig", .source = loop_ops },
    };
    const candidates = try lm.generate(a, loadCfg(a, phase2_cfg), &fs, null);

    // Each of the four previously-unwired modules now contributes mutants on code
    // that contains its target construct. Before wiring, generate() collected only
    // the four Phase-1 modules, so every assertion below failed (0 such mutants).
    try expect(hasOperator(candidates, "optional_orelse_unreachable"));
    try expect(hasOperator(candidates, "optional_null_check"));
    try expect(hasOperator(candidates, "error_catch_unreachable"));
    try expect(hasOperator(candidates, "errdefer_remove"));
    try expect(hasOperator(candidates, "integer_literal_boundary"));
    try expect(hasOperator(candidates, "loop_boundary"));
}

test "config rejects enabling a preview operator that has no collector" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // optional_orelse_default is a preview operator with no collector; enabling it
    // would load successfully and silently emit zero mutants, so config must
    // reject it instead (task 109). Stable operators still load.
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, config.load(a, "[mutators]\nenabled = [\"optional_orelse_default\"]\n", &diag));

    var diag_ok: config.Diagnostic = .{};
    const stable = try config.load(a, "[mutators]\nenabled = [\"optional_orelse_unreachable\"]\n", &diag_ok);
    try expectEqual(@as(usize, 1), stable.mutators_enabled.len);
}
