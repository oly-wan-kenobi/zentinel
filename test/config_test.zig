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

test "report.formats validates each element against the known formats (M5)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Every known format is accepted...
    var diag: config.Diagnostic = .{};
    const ok = try load(arena.allocator(), "[report]\nformats = [\"text\", \"json\", \"jsonl\", \"junit\"]\n", &diag);
    try expectEqual(@as(usize, 4), ok.report_formats.len);

    // ...but an unknown per-element value is rejected at load, not silently kept.
    var diag2: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[report]\nformats = [\"invalid_format\"]\n", &diag2));
    var diag3: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[report]\nformats = [\"json\", \"bogus\"]\n", &diag3));
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

test "multiple Zig modes are accepted by the safety-mode matrix (task 058)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // Task 058 lifts the pre-058 single-mode restriction: more than one
    // configured zig.modes entry is now accepted.
    var diag: config.Diagnostic = .{};
    const cfg = try load(arena.allocator(), "[zig]\nmodes = [\"Debug\", \"ReleaseSafe\"]\n", &diag);
    try expect(cfg.zig_modes.len == 2);
    // Unknown modes are still rejected, with or without multiple entries.
    var diag2: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[zig]\nmodes = [\"Debug\", \"Turbo\"]\n", &diag2));
    try expect(diag2.code == .invalid_value);
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

test "impact_graph selection is accepted after task 051" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    const cfg = try load(arena.allocator(),
        \\[project]
        \\name = "demo"
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\selection = "impact_graph"
        \\
    , &diag);
    try expectEqualStrings("impact_graph", cfg.test_selection);
}

test "an unknown selection strategy is still rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(),
        \\[project]
        \\name = "demo"
        \\
        \\[test]
        \\commands = ["zig build test"]
        \\selection = "call_graph"
        \\
    , &diag));
    try expectEqual(config.Code.invalid_value, diag.code);
    try expectEqualStrings("test", diag.section);
    try expectEqualStrings("selection", diag.key);
}

// --- Symlink-safe output containment (task 119, audit F-3) ------------------
//
// `config.isOutsideRoot` is string-only: it rejects absolute paths and `..`
// segments but never resolves symlinks, so an in-tree symlink that leaves the
// project tree slips past it and the report/cache write (which follows symlinks
// in the sub-path) lands outside the root. `outputPathHasSymlink` resolves
// containment by refusing any symlinked component in the output path (no-follow
// semantics, docs/SANDBOX_SECURITY.md). It reads the filesystem deterministically
// (like project_model.discover), so it lives next to isOutsideRoot in the
// deterministic core and is exercised here with a real temp directory + symlink.

test "outputPathHasSymlink flags a symlinked output component the string check misses (F-3)" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // An in-tree symlink whose target leaves the project root, and a legitimate
    // in-root output directory (a real directory, not a symlink).
    try tmp.dir.symLink(io, "../outside_root_target", "escape_link", .{});
    try tmp.dir.createDirPath(io, "out");

    // The existing string-only containment check misses the symlink: the path is
    // relative and has no `..` segment, so it cannot keep the write in-tree.
    try expect(!config.isOutsideRoot("escape_link/report.json"));

    // The symlink-aware check catches the escape, while legitimate in-root output
    // (a plain subdirectory or a bare filename) still passes.
    try expect(config.outputPathHasSymlink(io, tmp.dir, "escape_link/report.json"));
    try expect(!config.outputPathHasSymlink(io, tmp.dir, "out/report.json"));
    try expect(!config.outputPathHasSymlink(io, tmp.dir, "report.json"));
}

test "outputPathHasSymlink flags a symlinked final output file" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // An untrusted checkout could ship the report path itself as a symlink to an
    // out-of-root file; following it on write would clobber that file.
    try tmp.dir.symLink(io, "../outside.json", "report.json", .{});
    try expect(config.outputPathHasSymlink(io, tmp.dir, "report.json"));
}

test "pathEscapesRoot combines lexical and symlink containment for reads and writes" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.symLink(io, "../outside_root_target", "escape_link", .{});
    try tmp.dir.createDirPath(io, "docs");
    try tmp.dir.writeFile(io, .{ .sub_path = "docs/README.md", .data = "# ok\n" });

    try expect(config.pathEscapesRoot(io, tmp.dir, "/absolute/path"));
    try expect(config.pathEscapesRoot(io, tmp.dir, "docs/../outside.md"));
    try expect(config.pathEscapesRoot(io, tmp.dir, "escape_link/secret.md"));
    try expect(!config.pathEscapesRoot(io, tmp.dir, "docs/README.md"));
}
