// Layer: deterministic_core
//
// Privacy redaction for AI context (docs/AI_CONTEXT_SCHEMA.md "Privacy
// Requirements"). Pure and deterministic: it rewrites text by replacing every
// match of each configured redaction pattern with a fixed marker and reports
// which patterns matched. Redaction FAILS CLOSED -- an unsupported or malformed
// pattern returns `error.RedactionFailed` so the caller can abort the AI flow
// rather than risk leaking a secret it could not redact. The supported pattern
// subset is intentionally tiny (an optional `(?i)` case-insensitive flag, literal
// runs, and the single `[_-]?` optional-separator construct) so redaction stays
// auditable; anything richer is rejected, never silently ignored.
const std = @import("std");

pub const Error = error{RedactionFailed} || std.mem.Allocator.Error;

pub const marker = "[REDACTED]";

pub const Redacted = struct {
    text: []const u8,
    /// The configured patterns (verbatim) that matched at least once, in
    /// configuration order. Recorded in the AI context `privacy.redactions_applied`.
    applied: []const []const u8,
};

const Segment = struct {
    literal: []const u8,
    /// True when an optional `_` or `-` separator may precede this segment.
    optional_sep_before: bool,
};

/// A compiled redaction pattern: an optional case-insensitive flag and a list of
/// literal segments joined by optional `[_-]?` separators.
const Pattern = struct {
    case_insensitive: bool,
    segments: []const Segment,
};

fn isMeta(c: u8) bool {
    return switch (c) {
        '.', '*', '+', '?', '(', ')', '|', '^', '$', '{', '}', '\\' => true,
        else => false,
    };
}

/// Compile one configured pattern, or fail closed on anything outside the
/// supported subset.
fn compile(arena: std.mem.Allocator, pattern: []const u8) Error!Pattern {
    if (pattern.len == 0) return error.RedactionFailed;
    var rest = pattern;
    var ci = false;
    if (std.mem.startsWith(u8, rest, "(?i)")) {
        ci = true;
        rest = rest[4..];
    }
    if (rest.len == 0) return error.RedactionFailed;

    var segments: std.ArrayList(Segment) = .empty;
    var lit: std.ArrayList(u8) = .empty;
    var optional_sep_before = false;
    var i: usize = 0;
    while (i < rest.len) {
        if (std.mem.startsWith(u8, rest[i..], "[_-]?")) {
            // Flush the literal accumulated so far, then mark the next segment as
            // separable.
            if (lit.items.len > 0) {
                try segments.append(arena, .{ .literal = try arena.dupe(u8, lit.items), .optional_sep_before = optional_sep_before });
                lit.clearRetainingCapacity();
            }
            optional_sep_before = true;
            i += "[_-]?".len;
            continue;
        }
        if (isMeta(rest[i]) or rest[i] == '[' or rest[i] == ']') return error.RedactionFailed;
        try lit.append(arena, rest[i]);
        i += 1;
    }
    if (lit.items.len > 0) {
        try segments.append(arena, .{ .literal = try arena.dupe(u8, lit.items), .optional_sep_before = optional_sep_before });
    } else if (optional_sep_before) {
        // A trailing optional separator with no following literal is malformed.
        return error.RedactionFailed;
    }
    if (segments.items.len == 0) return error.RedactionFailed;
    return .{ .case_insensitive = ci, .segments = try segments.toOwnedSlice(arena) };
}

fn eqByte(a: u8, b: u8, ci: bool) bool {
    if (a == b) return true;
    if (!ci) return false;
    return std.ascii.toLower(a) == std.ascii.toLower(b);
}

/// Try to match `pat` at `text[start..]`. Returns the end index on success.
fn matchAt(pat: Pattern, text: []const u8, start: usize) ?usize {
    var pos = start;
    for (pat.segments, 0..) |seg, idx| {
        if (idx > 0 and seg.optional_sep_before) {
            if (pos < text.len and (text[pos] == '_' or text[pos] == '-')) pos += 1;
        }
        if (pos + seg.literal.len > text.len) return null;
        for (seg.literal, 0..) |c, k| {
            if (!eqByte(text[pos + k], c, pat.case_insensitive)) return null;
        }
        pos += seg.literal.len;
    }
    return pos;
}

/// Redact `text` with the configured `patterns`. Each match is replaced by
/// `marker`. Returns the rewritten text and the patterns that matched. Fails
/// closed when any pattern is unsupported or malformed.
pub fn redact(arena: std.mem.Allocator, text: []const u8, patterns: []const []const u8) Error!Redacted {
    var compiled: std.ArrayList(Pattern) = .empty;
    for (patterns) |p| try compiled.append(arena, try compile(arena, p));

    var applied_flags = try arena.alloc(bool, patterns.len);
    @memset(applied_flags, false);

    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        var matched = false;
        for (compiled.items, 0..) |pat, pi| {
            if (matchAt(pat, text, i)) |end| {
                if (end > i) {
                    try out.appendSlice(arena, marker);
                    applied_flags[pi] = true;
                    i = end;
                    matched = true;
                    break;
                }
            }
        }
        if (!matched) {
            try out.append(arena, text[i]);
            i += 1;
        }
    }

    var applied: std.ArrayList([]const u8) = .empty;
    for (patterns, 0..) |p, pi| {
        if (applied_flags[pi]) try applied.append(arena, p);
    }
    return .{ .text = try out.toOwnedSlice(arena), .applied = try applied.toOwnedSlice(arena) };
}
