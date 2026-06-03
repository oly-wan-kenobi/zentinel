// Layer: deterministic_core
//
// Typed doctest block metadata (docs/DOCTEST_BLOCK_FORMATS.md). The parser
// (src/doctest/parser.zig) produces these; case grouping/extraction is a later
// task. Explicit enums for language, kind, and match mode keep block
// classification deterministic.
const std = @import("std");

pub const Language = enum { zig, bash, json, text, toml, other };

/// Block kind from the info string. `unit_test` is the `test` tag (renamed to
/// avoid the Zig keyword); `none` is a plain language block (e.g. `zig`).
pub const Kind = enum { none, unit_test, compile_fail, expected, output, config, config_fail, before, after, cli };

pub const MatchMode = enum { none, subset, contains, exact, unordered };

pub const Block = struct {
    file: []const u8,
    /// 1-based line of the opening fence.
    line_start: u32,
    /// 1-based line of the closing fence.
    line_end: u32,
    /// Backtick count of the fence (3 or 4 for doctests; 5+ is documentation-only).
    fence_len: u8,
    /// Raw info string (trimmed) after the opening backticks.
    info: []const u8,
    /// Raw content bytes between the fences, preserved exactly.
    content: []const u8,
    language: Language,
    kind: Kind,
    match_mode: MatchMode,
    case_label: ?[]const u8,
    /// True only for a recognized, supported executable doctest block.
    is_doctest: bool,
};

pub fn languageFromToken(tok: []const u8) Language {
    if (std.mem.eql(u8, tok, "zig")) return .zig;
    if (std.mem.eql(u8, tok, "bash")) return .bash;
    if (std.mem.eql(u8, tok, "json")) return .json;
    if (std.mem.eql(u8, tok, "text")) return .text;
    if (std.mem.eql(u8, tok, "toml")) return .toml;
    return .other;
}

pub fn kindFromToken(tok: []const u8) ?Kind {
    if (std.mem.eql(u8, tok, "test")) return .unit_test;
    if (std.mem.eql(u8, tok, "compile_fail")) return .compile_fail;
    if (std.mem.eql(u8, tok, "expected")) return .expected;
    if (std.mem.eql(u8, tok, "output")) return .output;
    if (std.mem.eql(u8, tok, "config")) return .config;
    if (std.mem.eql(u8, tok, "config_fail")) return .config_fail;
    if (std.mem.eql(u8, tok, "before")) return .before;
    if (std.mem.eql(u8, tok, "after")) return .after;
    if (std.mem.eql(u8, tok, "cli")) return .cli;
    return null;
}

pub fn matchModeFromToken(tok: []const u8) ?MatchMode {
    if (std.mem.eql(u8, tok, "subset")) return .subset;
    if (std.mem.eql(u8, tok, "contains")) return .contains;
    if (std.mem.eql(u8, tok, "exact")) return .exact;
    // `unordered` selects order-insensitive JSON array matching (mapped to the
    // matcher's `json_unordered` mode in doctest_command.matchModeFor). Without
    // this entry the documented tag was rejected as unsupported, leaving the
    // implemented json_unordered match logic unreachable (M6).
    if (std.mem.eql(u8, tok, "unordered")) return .unordered;
    return null;
}
