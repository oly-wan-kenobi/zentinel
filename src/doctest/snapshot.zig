// Layer: deterministic_core
//
// Doctest snapshot orchestration (docs/DOCTEST_SPEC.md "Snapshot Tests"). It
// normalizes actual output, matches it against an expectation block under the
// requested mode, and produces a structured result with bounded expected/actual
// evidence and -- on mismatch -- a ZNTL_DOCTEST_SNAPSHOT_MISMATCH diagnostic
// carrying the file, line, and durable case id. Snapshot updates are manual and
// task-scoped: nothing here rewrites expected blocks. No execution occurs.
const std = @import("std");
const normalizer = @import("normalizer.zig");
const matcher = @import("matcher.zig");
const runner = @import("runner.zig");
const error_codes = @import("../error_codes.zig");

pub const excerpt_limit = 4096;

pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    file: []const u8,
    line: u32,
    case_id: []const u8,
};

pub const Result = struct {
    matched: bool,
    mode: matcher.Mode,
    case_id: []const u8,
    file: []const u8,
    line: u32,
    expected_excerpt: []const u8,
    actual_excerpt: []const u8,
    normalized_expected: []const u8,
    normalized_actual: []const u8,
    /// ZNTL_DOCTEST_SNAPSHOT_MISMATCH diagnostic when `matched` is false, else null.
    diagnostic: ?Diagnostic,
};

/// Normalize `actual`, match it against `expected` under `mode`, and build a
/// structured result. A regex `expected` is treated as a pattern and is not
/// normalized; every other mode normalizes both sides identically.
pub fn compare(
    arena: std.mem.Allocator,
    case_id: []const u8,
    file: []const u8,
    line: u32,
    mode: matcher.Mode,
    expected: []const u8,
    actual: []const u8,
    opts: normalizer.Options,
) std.mem.Allocator.Error!Result {
    const norm_actual = try normalizer.normalize(arena, actual, opts);
    const norm_expected = if (mode == .regex)
        try arena.dupe(u8, expected)
    else
        try normalizer.normalize(arena, expected, opts);

    const matched = try matcher.match(arena, mode, norm_expected, norm_actual);

    var diag: ?Diagnostic = null;
    if (!matched) {
        diag = .{
            .code = error_codes.doctest_snapshot_mismatch,
            .message = "doctest output did not match the expected snapshot",
            .file = file,
            .line = line,
            .case_id = case_id,
        };
    }

    return .{
        .matched = matched,
        .mode = mode,
        .case_id = case_id,
        .file = file,
        .line = line,
        .expected_excerpt = try bounded(arena, expected),
        .actual_excerpt = try bounded(arena, actual),
        .normalized_expected = try bounded(arena, norm_expected),
        .normalized_actual = try bounded(arena, norm_actual),
        .diagnostic = diag,
    };
}

/// Compare a doctest case's actual stdout (from the runner) against an
/// expectation block.
pub fn matchResultOutput(
    arena: std.mem.Allocator,
    result: runner.CaseResult,
    file: []const u8,
    line: u32,
    mode: matcher.Mode,
    expected: []const u8,
    opts: normalizer.Options,
) std.mem.Allocator.Error!Result {
    return compare(arena, result.id, file, line, mode, expected, result.stdout_excerpt, opts);
}

/// Deterministic multi-line mismatch report for diagnostics and snapshots.
pub fn renderDiagnostic(arena: std.mem.Allocator, r: Result) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    if (r.diagnostic) |d| {
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "{s} at {s}:{d} ({s})\n", .{ d.code, d.file, d.line, d.case_id }));
    } else {
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "match at {s}:{d} ({s})\n", .{ r.file, r.line, r.case_id }));
    }
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "mode: {s}\n", .{r.mode.toString()}));
    try out.appendSlice(arena, "--- expected (normalized) ---\n");
    try out.appendSlice(arena, std.mem.trimEnd(u8, r.normalized_expected, "\n"));
    try out.appendSlice(arena, "\n--- actual (normalized) ---\n");
    try out.appendSlice(arena, std.mem.trimEnd(u8, r.normalized_actual, "\n"));
    try out.appendSlice(arena, "\n");
    return out.toOwnedSlice(arena);
}

fn bounded(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    const len = @min(text.len, excerpt_limit);
    return arena.dupe(u8, text[0..len]);
}
