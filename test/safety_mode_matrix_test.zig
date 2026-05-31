const std = @import("std");
const zentinel = @import("zentinel");

const safety_modes = zentinel.safety_modes;
const report = zentinel.report;
const config = zentinel.config;
const run_command = zentinel.run_command;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

// --- Mode model ------------------------------------------------------------

test "canonical mode order is Debug, ReleaseSafe, ReleaseFast, ReleaseSmall" {
    try expectEqual(@as(usize, 4), safety_modes.canonical_order.len);
    try expectEqual(report.Mode.Debug, safety_modes.canonical_order[0]);
    try expectEqual(report.Mode.ReleaseSafe, safety_modes.canonical_order[1]);
    try expectEqual(report.Mode.ReleaseFast, safety_modes.canonical_order[2]);
    try expectEqual(report.Mode.ReleaseSmall, safety_modes.canonical_order[3]);
}

test "parse accepts the four modes and rejects unknown" {
    try expectEqual(report.Mode.Debug, safety_modes.parse("Debug").?);
    try expectEqual(report.Mode.ReleaseFast, safety_modes.parse("ReleaseFast").?);
    try expect(safety_modes.parse("Turbo") == null);
    try expect(safety_modes.parse("") == null);
}

test "buildFlag maps modes to the -O optimize flag" {
    try expectEqualStrings("-ODebug", safety_modes.buildFlag(.Debug));
    try expectEqualStrings("-OReleaseFast", safety_modes.buildFlag(.ReleaseFast));
    try expectEqualStrings("-OReleaseSafe", safety_modes.buildFlag(.ReleaseSafe));
    try expectEqualStrings("-OReleaseSmall", safety_modes.buildFlag(.ReleaseSmall));
}

test "primaryMode honors the override, else the first configured mode, else Debug" {
    try expectEqual(report.Mode.ReleaseFast, safety_modes.primaryMode(&.{"Debug"}, .ReleaseFast));
    try expectEqual(report.Mode.ReleaseSafe, safety_modes.primaryMode(&.{ "ReleaseSafe", "Debug" }, null));
    try expectEqual(report.Mode.Debug, safety_modes.primaryMode(&.{}, null));
}

test "matrixModes: override yields a single mode; config yields canonical-sorted unique" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const single = try safety_modes.matrixModes(arena, &.{ "Debug", "ReleaseFast" }, .ReleaseFast);
    try expectEqual(@as(usize, 1), single.len);
    try expectEqual(report.Mode.ReleaseFast, single[0]);

    // Config order ReleaseFast, Debug is canonicalized to Debug, ReleaseFast and deduped.
    const multi = try safety_modes.matrixModes(arena, &.{ "ReleaseFast", "Debug", "ReleaseFast" }, null);
    try expectEqual(@as(usize, 2), multi.len);
    try expectEqual(report.Mode.Debug, multi[0]);
    try expectEqual(report.Mode.ReleaseFast, multi[1]);

    const default = try safety_modes.matrixModes(arena, &.{}, null);
    try expectEqual(@as(usize, 1), default.len);
    try expectEqual(report.Mode.Debug, default[0]);
}

// --- Distinguishing mode effects from uniform outcomes ---------------------

test "isModeDependent flags a mutant whose status differs across modes" {
    // Debug vs ReleaseFast fixture behavior: an overflow-sensitive mutant is
    // killed by the Debug safety check but survives in ReleaseFast where the
    // check is elided. That difference is a mode effect, not a flaky test.
    const mode_effect = [_]report.ModeResult{
        .{ .mode = .Debug, .status = .killed },
        .{ .mode = .ReleaseFast, .status = .survived },
    };
    try expect(safety_modes.isModeDependent(&mode_effect));

    // A uniformly killed mutant is not mode-dependent.
    const uniform = [_]report.ModeResult{
        .{ .mode = .Debug, .status = .killed },
        .{ .mode = .ReleaseFast, .status = .killed },
    };
    try expect(!safety_modes.isModeDependent(&uniform));
}

test "sortModeResults orders by canonical mode rank" {
    var rows = [_]report.ModeResult{
        .{ .mode = .ReleaseFast, .status = .survived },
        .{ .mode = .Debug, .status = .killed },
        .{ .mode = .ReleaseSmall, .status = .survived },
    };
    safety_modes.sortModeResults(&rows);
    try expectEqual(report.Mode.Debug, rows[0].mode);
    try expectEqual(report.Mode.ReleaseFast, rows[1].mode);
    try expectEqual(report.Mode.ReleaseSmall, rows[2].mode);
}

// --- Report model: additive result.mode_matrix -----------------------------

test "result.mode_matrix is omitted when null (single-mode reports unchanged)" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const result = report.Result{
        .status = .killed,
        .mode = .Debug,
        .commands = &.{},
        .duration_ms = 0,
        .evidence = .{},
        .skip_reason = null,
        .mode_matrix = null,
    };
    const json = try std.json.Stringify.valueAlloc(arena, result, .{});
    try expect(std.mem.indexOf(u8, json, "mode_matrix") == null);
    try expect(std.mem.indexOf(u8, json, "\"mode\":\"Debug\"") != null);
}

test "result.mode_matrix is emitted when present, preserving result.mode" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const matrix = [_]report.ModeResult{
        .{ .mode = .Debug, .status = .killed },
        .{ .mode = .ReleaseFast, .status = .survived },
    };
    const result = report.Result{
        .status = .killed,
        .mode = .Debug,
        .commands = &.{},
        .duration_ms = 0,
        .evidence = .{},
        .skip_reason = null,
        .mode_matrix = &matrix,
    };
    const json = try std.json.Stringify.valueAlloc(arena, result, .{});
    try expect(std.mem.indexOf(u8, json, "\"mode_matrix\"") != null);
    try expect(std.mem.indexOf(u8, json, "\"mode\":\"Debug\"") != null); // result.mode preserved
    try expect(std.mem.indexOf(u8, json, "ReleaseFast") != null);
}

// --- Config: multiple modes accepted only now ------------------------------

test "config accepts multiple zig.modes now that the safety-mode matrix exists" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var diag: config.Diagnostic = .{};
    const cfg = try config.load(arena, "[zig]\nmodes = [\"Debug\", \"ReleaseFast\"]\n", &diag);
    try expectEqual(@as(usize, 2), cfg.zig_modes.len);

    // Unknown modes are still rejected.
    var diag2: config.Diagnostic = .{};
    try expectError(error.Invalid, config.load(arena, "[zig]\nmodes = [\"Turbo\"]\n", &diag2));
}

// --- run-command --mode override -------------------------------------------

test "run --mode parses a valid mode and rejects an invalid one" {
    try expectEqual(report.Mode.ReleaseFast, (try run_command.parseArgs(&.{ "--mode", "ReleaseFast" })).mode_override.?);
    try expectEqual(report.Mode.Debug, (try run_command.parseArgs(&.{ "--mode", "Debug" })).mode_override.?);
    try expect((try run_command.parseArgs(&.{})).mode_override == null);
    try expectError(error.InvalidMode, run_command.parseArgs(&.{ "--mode", "Turbo" }));
    try expectError(error.MissingValue, run_command.parseArgs(&.{"--mode"}));
}

// The report.v1 schema file gains the optional result.mode_matrix property
// (not in `required`, additionalProperties stays false) and docs/REPORT_FORMAT.md
// documents it as an additive zentinel.report.v1 extension; both the schema JSON
// validity and the documentation phrases are enforced by
// scripts/validate_task_system.py. The serialization tests above prove the report
// model represents mode_matrix additively while preserving result.mode.

// --- Debug versus ReleaseFast fixture --------------------------------------

const overflow_fixture = @embedFile("fixtures/safety_modes/overflow.zig");

test "the Debug-vs-ReleaseFast fixture carries a safety-mode-sensitive mutation point" {
    // The comparison boundary plus the overflow-prone increment are the mutation
    // point whose status differs between Debug (overflow safety check kills it)
    // and ReleaseFast (check elided, the mutant survives).
    try expect(std.mem.indexOf(u8, overflow_fixture, "acc < 255") != null);
    try expect(std.mem.indexOf(u8, overflow_fixture, "acc + 1") != null);
}
