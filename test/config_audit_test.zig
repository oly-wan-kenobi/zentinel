// Cluster: config audit fixes (M2, C1, C5, C4, C7).
//
// Guards against meaningless-but-clean config that previously validated and then
// disabled work silently (empty mutators.enabled / project.include), against a
// TOML value followed by a stray token being misreported as a missing '=', and
// against `selection = "impact_graph"` being accepted as a false strategy alias.
const std = @import("std");
const zentinel = @import("zentinel");
const config = zentinel.config;
const toml = zentinel.config_toml;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

fn load(a: std.mem.Allocator, src: []const u8, diag: *config.Diagnostic) config.Error!config.Config {
    return config.load(a, src, diag);
}

// --- M2: empty mutators.enabled is rejected ----------------------------------

test "explicit empty mutators.enabled is rejected, not a silent no-op" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `enabled = []` validates clean (every element is trivially a known mutator)
    // but expands to nothing, disabling all mutation. That is meaningless intent,
    // not a silently-accepted no-op -- mirror the zig.modes empty-guard.
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(a, "[mutators]\nenabled = []\n", &diag));
    try expectEqual(config.Code.invalid_value, diag.code);
    try expectEqualStrings("mutators", diag.section);
    try expectEqualStrings("enabled", diag.key);

    // Omitting `enabled` keeps the phase1 default (6 stable operators).
    var d2: config.Diagnostic = .{};
    const dflt = try load(a, "", &d2);
    try expectEqual(@as(usize, 6), dflt.mutators_enabled.len);
}

// --- C1: empty project.include is rejected -----------------------------------

test "explicit empty project.include is rejected, not a silent no-op" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `include = []` validates clean but selects no files to mutate. Reject it as
    // meaningless intent; omitting `include` keeps the default glob.
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(a, "[project]\ninclude = []\n", &diag));
    try expectEqual(config.Code.invalid_value, diag.code);
    try expectEqualStrings("project", diag.section);
    try expectEqualStrings("include", diag.key);

    // A non-empty include still loads; omitting it keeps the documented default.
    var d2: config.Diagnostic = .{};
    const ok = try load(a, "[project]\ninclude = [\"src/**/*.zig\"]\n", &d2);
    try expectEqual(@as(usize, 1), ok.include.len);

    var d3: config.Diagnostic = .{};
    const dflt = try load(a, "", &d3);
    try expect(dflt.include.len >= 1);
}

// --- C5: rejection messages name the offending mutator -----------------------

test "unknown mutator rejection names the offending operator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[mutators]\nenabled = [\"make_it_fast\"]\n", &diag));
    try expectEqual(config.Code.invalid_value, diag.code);
    // The offending name must appear in the message so the user can find it.
    try expect(std.mem.indexOf(u8, diag.message, "make_it_fast") != null);
}

test "preview-only mutator rejection names the offending operator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // `optional_orelse_default` is a registered but preview-only operator: it is a
    // known name (so it hits the preview branch, not the unknown branch) and must
    // be rejected with its name in the message.
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(arena.allocator(), "[mutators]\nenabled = [\"optional_orelse_default\"]\n", &diag));
    try expectEqual(config.Code.invalid_value, diag.code);
    try expect(std.mem.indexOf(u8, diag.message, "optional_orelse_default") != null);
    try expect(std.mem.indexOf(u8, diag.message, "preview") != null);
}

// --- C4: a stray token after a value is a value error, not a key error -------

test "a trailing token after a value reports unexpected-token, not expected '='" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `timeout_ms = 30 000` used to surface as "expected '=' after key" when the
    // parser read `000` as the next bare key; it must report the real fault: a
    // second token after the value.
    var pdiag: toml.Diagnostic = .{};
    try expectError(error.ParseError, toml.parse(a, "[test]\ntimeout_ms = 30 000\n", &pdiag));
    try expect(std.mem.indexOf(u8, pdiag.message, "unexpected token after value") != null);

    // It surfaces through config.load as a parse_error too.
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(a, "[test]\ntimeout_ms = 30 000\n", &diag));
    try expectEqual(config.Code.parse_error, diag.code);

    // A trailing token after a string/boolean is caught the same way.
    var pdiag2: toml.Diagnostic = .{};
    try expectError(error.ParseError, toml.parse(a, "[project]\nname = \"x\" oops\n", &pdiag2));
    try expect(std.mem.indexOf(u8, pdiag2.message, "unexpected token after value") != null);

    var pdiag3: toml.Diagnostic = .{};
    try expectError(error.ParseError, toml.parse(a, "[cache]\nenabled = true false\n", &pdiag3));
    try expect(std.mem.indexOf(u8, pdiag3.message, "unexpected token after value") != null);
}

test "a value followed only by inline space, a comment, or EOF still parses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The trailing-token guard must not reject legitimate trailing trivia: inline
    // whitespace, an inline comment, and end-of-file with no newline.
    var diag: toml.Diagnostic = .{};
    const doc = try toml.parse(a, "[test]\ntimeout_ms = 30   # the timeout\n", &diag);
    try expectEqual(@as(usize, 1), doc.entries.len);
    try expectEqual(@as(i64, 30), doc.entries[0].value.integer);

    var d2: toml.Diagnostic = .{};
    const doc2 = try toml.parse(a, "[run]\njobs = 2", &d2); // no trailing newline
    try expectEqual(@as(usize, 1), doc2.entries.len);
    try expectEqual(@as(i64, 2), doc2.entries[0].value.integer);

    // A multi-line array value (its `]` is the value terminator) still parses, and
    // a comment may follow it on the same line.
    var d3: toml.Diagnostic = .{};
    const doc3 = try toml.parse(a, "[project]\ninclude = [\"a.zig\"] # note\n", &d3);
    try expectEqual(@as(usize, 1), doc3.entries.len);
}

// --- C7: impact_graph is rejected by config validation -----------------------

test "selection = impact_graph is rejected (reserved alias)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // impact_graph's resolver is an exact alias of same_file_then_package today, so
    // accepting it would record a false strategy. Reject it; the enum variant is
    // kept only for forward-compat.
    var diag: config.Diagnostic = .{};
    try expectError(error.Invalid, load(a, "[test]\nselection = \"impact_graph\"\n", &diag));
    try expectEqual(config.Code.invalid_value, diag.code);
    try expectEqualStrings("test", diag.section);
    try expectEqualStrings("selection", diag.key);

    // The real strategies still load.
    inline for (.{ "same_file_then_package", "same_file", "package", "all" }) |sel| {
        var d: config.Diagnostic = .{};
        const cfg = try load(a, "[test]\nselection = \"" ++ sel ++ "\"\n", &d);
        try expectEqualStrings(sel, cfg.test_selection);
    }
}
