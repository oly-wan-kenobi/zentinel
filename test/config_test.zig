const std = @import("std");
const zentinel = @import("zentinel");
const config = zentinel.config;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

const full_config = @embedFile("snapshots/init_config.toml");

fn load(a: std.mem.Allocator, src: []const u8, diag: *config.Diagnostic) config.Error!config.Config {
    return config.load(a, src, diag);
}

test "empty config normalizes to documented defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    const cfg = try load(arena.allocator(), "", &diag);
    try expectEqualStrings("example", cfg.project_name);
    try expectEqualStrings("ast", cfg.backend_default);
    try expectEqual(@as(i64, 1), cfg.run_jobs);
    try expectEqual(@as(i64, 30000), cfg.test_timeout_ms);
    try expect(cfg.baseline_required);
    try expectEqual(@as(usize, 3), cfg.exclude.len);
    try expectEqualStrings(".zig-cache/**", cfg.exclude[0]);
    try expectEqualStrings("zig-out/**", cfg.exclude[1]);
    try expectEqualStrings("test/**", cfg.exclude[2]);
}

test "minimal config parses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    const cfg = try load(arena.allocator(),
        \\[project]
        \\name = "demo"
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\
    , &diag);
    try expectEqualStrings("demo", cfg.project_name);
    try expectEqual(@as(usize, 1), cfg.test_commands.len);
}

test "full default config (task 001 init output) parses with expected fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    const cfg = try load(arena.allocator(), full_config, &diag);
    try expectEqualStrings("example", cfg.project_name);
    try expectEqual(@as(usize, 6), cfg.mutators_enabled.len);
    try expect(!cfg.ai_enabled);
    try expectEqualStrings("disabled", cfg.ai_provider);
    try expectEqual(@as(usize, 2), cfg.report_formats.len);
}

test "parser accepts tables, strings, booleans, integers, arrays, and comments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    const cfg = try load(arena.allocator(),
        \\# a comment
        \\[cache]
        \\enabled = false   # inline comment
        \\directory = "build/cache"
        \\
        \\[run]
        \\jobs = 1
        \\
        \\[project]
        \\include = ["a.zig", "b.zig"]
        \\
    , &diag);
    try expect(!cfg.cache_enabled);
    try expectEqualStrings("build/cache", cfg.cache_directory);
    try expectEqual(@as(usize, 2), cfg.include.len);
}

test "unsupported TOML syntax fails with parse_error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[project]\nname = { inline = true }\n", &diag));
    try expect(diag.code == .parse_error);
}

test "unknown key is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[project]\nbogus = \"x\"\n", &diag));
    try expect(diag.code == .unknown_key);
    try expectEqualStrings("project", diag.section);
    try expectEqualStrings("bogus", diag.key);
}

test "unknown section is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[nope]\nx = 1\n", &diag));
    try expect(diag.code == .unknown_key);
}

test "wrong value type is rejected with invalid_value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[run]\njobs = \"two\"\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "invalid Zig mode is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[zig]\nmodes = [\"Turbo\"]\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "multiple Zig modes are rejected before task 058" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[zig]\nmodes = [\"Debug\", \"ReleaseSafe\"]\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "experimental backend without opt-in is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[backend]\ndefault = \"zir\"\n", &diag));
    try expect(diag.code == .experimental_backend);
}

test "negative timeout is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[test]\ntimeout_ms = -1\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "baseline_required = false is reserved and rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[test]\nbaseline_required = false\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "empty test command list is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[test]\ncommands = []\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "unknown mutator name is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[mutators]\nenabled = [\"make_it_fast\"]\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "output directory outside project root is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[report]\noutput_dir = \"../escape\"\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "non-positive worker count is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[run]\njobs = 0\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "remote AI provider without remote_allowed is rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[ai]\nprovider = \"remote\"\n", &diag));
    try expect(diag.code == .invalid_value);
}

test "mutator special values expand deterministically" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diag: config.Diagnostic = .{};

    const p1 = try load(a, "[mutators]\nenabled = [\"phase1\"]\n", &diag);
    try expectEqual(@as(usize, 6), p1.mutators_enabled.len);
    try expectEqualStrings("arithmetic_add_sub", p1.mutators_enabled[0]);

    const p2 = try load(a, "[mutators]\nenabled = [\"phase2\"]\n", &diag);
    try expectEqual(@as(usize, 6), p2.mutators_enabled.len);

    const all = try load(a, "[mutators]\nenabled = [\"all_stable\"]\n", &diag);
    try expectEqual(@as(usize, 12), all.mutators_enabled.len);
}

test "path normalization converts backslashes to forward slashes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    const cfg = try load(arena.allocator(), "[cache]\ndirectory = \"build\\cache\"\n", &diag);
    try expectEqualStrings("build/cache", cfg.cache_directory);
}

test "config-aware init output parses with the custom test command" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try zentinel.initConfigText(a, "zig build test -Dfoo");
    var diag: config.Diagnostic = .{};
    const cfg = try load(a, text, &diag);
    try expectEqual(@as(usize, 1), cfg.test_commands.len);
    try expectEqualStrings("zig build test -Dfoo", cfg.test_commands[0]);
}

test "default init output equals the static template" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try zentinel.initConfigText(arena.allocator(), null);
    try expectEqualStrings(zentinel.default_config, text);
}
