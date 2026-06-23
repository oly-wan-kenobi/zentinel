// Layer: deterministic_core
//
// Safety/optimization mode matrix (docs/ZIG_SEMANTICS.md, docs/REPORT_FORMAT.md).
// Models the four Zig build modes explicitly, their canonical order,
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

/// The `-O<mode>` optimize flag for a `zig test`/`build-exe` command.
pub fn buildFlag(mode: Mode) []const u8 {
    return switch (mode) {
        .Debug => "-ODebug",
        .ReleaseSafe => "-OReleaseSafe",
        .ReleaseFast => "-OReleaseFast",
        .ReleaseSmall => "-OReleaseSmall",
    };
}

/// Index of the first bare `--` argument-separator token in `argv`, or null when
/// there is none. Everything at and after `--` is opaque passthrough to the
/// wrapped program (for `zig build`, forwarded to the built artifact / test
/// binary), so a build option placed there is silently ignored by `zig build`.
fn firstSeparator(argv: []const []const u8) ?usize {
    for (argv, 0..) |a, i| {
        if (std.mem.eql(u8, a, "--")) return i;
    }
    return null;
}

/// Insert `flag` into `argv` at `at`, shifting the tail right by one. `at` in
/// `[0, argv.len]`; `at == argv.len` is an append.
fn insertFlagAt(arena: std.mem.Allocator, argv: []const []const u8, at: usize, flag: []const u8) std.mem.Allocator.Error![]const []const u8 {
    const out = try arena.alloc([]const u8, argv.len + 1);
    @memcpy(out[0..at], argv[0..at]);
    out[at] = flag;
    @memcpy(out[at + 1 ..], argv[at..]);
    return out;
}

/// Return `argv` with the optimize flag for `mode` inserted, so a mutant is
/// actually evaluated under that mode -- the mode must reach the spawned process
/// as a real argv element, not merely a `result.mode` label. The flag form
/// is command-specific and verified against pinned Zig 0.16:
///   - `zig test ...`  takes `-O<mode>`            (e.g. `-OReleaseFast`)
///   - `zig build ...` takes `-Doptimize=<mode>`   (`zig build` REJECTS `-O<mode>`)
/// `Debug` is the compiler default and any non-`zig` command has no known optimize
/// flag, so both are returned unchanged -- the default/no-`--mode` path is then
/// byte-for-byte identical to before, and custom test commands are never broken.
///
/// The build flag is inserted BEFORE the first `--` separator, not appended:
/// `zig build` treats everything after `--` as opaque passthrough to the built
/// program (e.g. `zig build test -- --filter x`), so an appended `-Doptimize=...`
/// would land in the passthrough region and be ignored -- silently running every
/// `--mode`/matrix verdict in Debug. Inserting before `--` (or appending when
/// there is none) keeps the flag a real `zig build` argument. The `zig test`
/// form has no such separator-sensitivity and is appended.
pub fn argvForMode(arena: std.mem.Allocator, argv: []const []const u8, mode: Mode) std.mem.Allocator.Error![]const []const u8 {
    if (mode == .Debug) return argv;
    if (argv.len < 2 or !std.mem.eql(u8, argv[0], "zig")) return argv;
    if (std.mem.eql(u8, argv[1], "test")) {
        return insertFlagAt(arena, argv, argv.len, buildFlag(mode));
    }
    if (std.mem.eql(u8, argv[1], "build")) {
        const flag = try std.fmt.allocPrint(arena, "-Doptimize={s}", .{@tagName(mode)});
        // Insert before the first `--`; absent any separator this appends.
        const at = firstSeparator(argv) orelse argv.len;
        return insertFlagAt(arena, argv, at, flag);
    }
    return argv;
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
