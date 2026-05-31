// Layer: deterministic_core
//
// Safety/optimization mode matrix (docs/ZIG_SEMANTICS.md, docs/REPORT_FORMAT.md,
// task 058). Models the four Zig build modes explicitly, their canonical order,
// the `--mode` override resolution, and the deterministic classification that
// distinguishes a safety-mode effect (a mutant whose status differs across modes,
// e.g. killed by a Debug safety check but surviving in ReleaseFast where the check
// is elided) from a uniform outcome. Pure: no execution. Mode-matrix reporting is
// an additive `zentinel.report.v1` extension (optional `result.mode_matrix`) that
// preserves `result.mode` semantics.
const std = @import("std");
const report = @import("report.zig");

pub const Mode = report.Mode;

/// The canonical, deterministic mode order used for sorting matrix output.
pub const canonical_order = [_]Mode{ .Debug, .ReleaseSafe, .ReleaseFast, .ReleaseSmall };

pub fn parse(name: []const u8) ?Mode {
    inline for (canonical_order) |m| {
        if (std.mem.eql(u8, name, @tagName(m))) return m;
    }
    return null;
}

/// The `-O<mode>` optimize flag for a build/test command.
pub fn buildFlag(mode: Mode) []const u8 {
    return switch (mode) {
        .Debug => "-ODebug",
        .ReleaseSafe => "-OReleaseSafe",
        .ReleaseFast => "-OReleaseFast",
        .ReleaseSmall => "-OReleaseSmall",
    };
}

/// Rank of a mode in canonical order (used for deterministic sorting).
pub fn rank(mode: Mode) usize {
    for (canonical_order, 0..) |m, i| {
        if (m == mode) return i;
    }
    return canonical_order.len;
}

/// The primary execution mode reflected in `result.mode`: the `--mode` override
/// if given, else the first configured mode, else Debug.
pub fn primaryMode(config_modes: []const []const u8, override: ?Mode) Mode {
    if (override) |o| return o;
    if (config_modes.len > 0) {
        if (parse(config_modes[0])) |m| return m;
    }
    return .Debug;
}

/// The set of modes to run for the matrix: just the override when given, else the
/// configured modes deduped and sorted into canonical order (default Debug).
pub fn matrixModes(arena: std.mem.Allocator, config_modes: []const []const u8, override: ?Mode) std.mem.Allocator.Error![]Mode {
    if (override) |o| {
        const out = try arena.alloc(Mode, 1);
        out[0] = o;
        return out;
    }
    var present = [_]bool{false} ** canonical_order.len;
    for (config_modes) |name| {
        if (parse(name)) |m| present[rank(m)] = true;
    }
    var count: usize = 0;
    for (present) |p| {
        if (p) count += 1;
    }
    if (count == 0) {
        present[rank(.Debug)] = true;
        count = 1;
    }
    const out = try arena.alloc(Mode, count);
    var k: usize = 0;
    for (canonical_order, 0..) |m, i| {
        if (present[i]) {
            out[k] = m;
            k += 1;
        }
    }
    return out;
}

fn lessModeResult(_: void, a: report.ModeResult, b: report.ModeResult) bool {
    return rank(a.mode) < rank(b.mode);
}

/// Sort mode-matrix rows by canonical mode rank for deterministic report output.
pub fn sortModeResults(rows: []report.ModeResult) void {
    std.mem.sort(report.ModeResult, rows, {}, lessModeResult);
}

/// True when a mutant's status differs across modes -- a safety-mode effect that
/// must be distinguished from a uniform kill/survive or a normal test failure.
pub fn isModeDependent(matrix: []const report.ModeResult) bool {
    if (matrix.len < 2) return false;
    const first = matrix[0].status;
    for (matrix[1..]) |row| {
        if (row.status != first) return true;
    }
    return false;
}
