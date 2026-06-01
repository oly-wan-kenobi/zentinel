// Layer: deterministic_core
//
// Privacy redaction for AI context (docs/AI_CONTEXT_SCHEMA.md "Privacy
// Requirements"). Pure and deterministic: it rewrites text by replacing every
// match of each configured redaction pattern with a fixed marker and reports
// which patterns matched. Configured patterns mask known secret LABELS
// (api_key, token); on top of them a fixed set of built-in matchers redacts the
// secret VALUES themselves (GitHub, AWS, Anthropic, JWT, and PEM private-key
// shapes) so an unlabeled credential, or the value after a label, cannot reach a
// provider. Redaction FAILS CLOSED -- an unsupported or malformed configured
// pattern returns `error.RedactionFailed` so the caller can abort the AI flow
// rather than risk leaking a secret it could not redact. The supported
// configured-pattern subset is intentionally tiny (an optional `(?i)`
// case-insensitive flag, literal runs, and the single `[_-]?` optional-separator
// construct) so redaction stays auditable; anything richer is rejected, never
// silently ignored.
const std = @import("std");

pub const Error = error{RedactionFailed} || std.mem.Allocator.Error;

pub const marker = "[REDACTED]";

pub const Redacted = struct {
    text: []const u8,
    /// The configured patterns (verbatim) that matched at least once, in
    /// configuration order. Recorded in the AI context `privacy.redactions_applied`.
    applied: []const []const u8,
    /// True if at least one built-in secret-VALUE shape (GitHub/AWS/Anthropic/JWT/
    /// PEM) matched. Built-in matches are not configured patterns, so they are not
    /// in `applied`; the caller records them under a synthetic label so
    /// `redactions_applied` stays truthful about value scrubbing.
    builtin_matched: bool = false,
};

/// True for a byte that can appear inside a filesystem path token.
fn isPathByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '/' or c == '.' or c == '_' or c == '-';
}

/// Normalize absolute-path tokens in `text` to the `<path>` placeholder so an
/// absolute developer path (which can itself embed a secret-looking segment)
/// never reaches a provider or the rendered AI output (docs/AI_CONTEXT_SCHEMA.md).
/// A token qualifies when a `/` begins a path-byte run at a token boundary (start
/// of text or after a non-path byte) and that run contains a second `/` -- the
/// multi-segment requirement keeps a lone division operator (`a / b`) and
/// in-tree relative paths (`src/x.zig`, `./x.zig`) untouched, so the AI still
/// sees the mutated code. Pure and deterministic.
pub fn normalizeAbsolutePaths(arena: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!struct { text: []const u8, changed: bool } {
    var out: std.ArrayList(u8) = .empty;
    var changed = false;
    var i: usize = 0;
    while (i < text.len) {
        const at_boundary = i == 0 or !isPathByte(text[i - 1]);
        if (text[i] == '/' and at_boundary) {
            var end = i + 1;
            var inner_slashes: usize = 0;
            while (end < text.len and isPathByte(text[end])) : (end += 1) {
                if (text[end] == '/') inner_slashes += 1;
            }
            if (inner_slashes >= 1) {
                try out.appendSlice(arena, "<path>");
                changed = true;
                i = end;
                continue;
            }
        }
        try out.append(arena, text[i]);
        i += 1;
    }
    return .{ .text = try out.toOwnedSlice(arena), .changed = changed };
}

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

// --- Built-in secret VALUE shapes ------------------------------------------
//
// Configured patterns (above) mask known secret LABELS (api_key, token). They
// do not mask the VALUE that follows a label, and they cannot catch a secret
// that appears with no label at all. These built-in matchers close that gap:
// each recognizes the *shape* of a common credential and redacts the value
// itself, regardless of any surrounding label. They are hardcoded, not user
// input, so they have no compile step and cannot be malformed -- the fail-closed
// contract applies only to the configured patterns. A built-in match emits the
// same `marker`; it is not added to `Redacted.applied`, which records only the
// configured patterns that matched.

fn isUpperAlnum(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9');
}

/// GitHub / JWT / Anthropic value bodies: URL-safe base64 plus `_` and `-`.
fn isTokenBody(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

/// Length of the run of bytes at `text[start..]` for which `pred` holds.
fn runLen(text: []const u8, start: usize, comptime pred: fn (u8) bool) usize {
    var n: usize = 0;
    while (start + n < text.len and pred(text[start + n])) n += 1;
    return n;
}

const github_prefixes = [_][]const u8{ "ghp_", "gho_", "ghu_", "ghs_", "ghr_", "github_pat_" };

/// A GitHub token: a `gh*_`/`github_pat_` prefix and >= 20 token-body bytes.
fn matchGithub(text: []const u8, start: usize) ?usize {
    for (github_prefixes) |pfx| {
        if (std.mem.startsWith(u8, text[start..], pfx)) {
            const body = start + pfx.len;
            const n = runLen(text, body, isTokenBody);
            if (n >= 20) return body + n;
        }
    }
    return null;
}

const aws_prefixes = [_][]const u8{ "AKIA", "ASIA" };

/// An AWS access key id: `AKIA`/`ASIA` and >= 16 uppercase alphanumerics.
fn matchAws(text: []const u8, start: usize) ?usize {
    for (aws_prefixes) |pfx| {
        if (std.mem.startsWith(u8, text[start..], pfx)) {
            const body = start + pfx.len;
            const n = runLen(text, body, isUpperAlnum);
            if (n >= 16) return body + n;
        }
    }
    return null;
}

/// An Anthropic API key: `sk-ant-` and >= 8 token-body bytes.
fn matchAnthropic(text: []const u8, start: usize) ?usize {
    const pfx = "sk-ant-";
    if (!std.mem.startsWith(u8, text[start..], pfx)) return null;
    const body = start + pfx.len;
    const n = runLen(text, body, isTokenBody);
    return if (n >= 8) body + n else null;
}

/// A JSON Web Token: `eyJ`-prefixed header `.` payload `.` signature, each a
/// non-empty base64url run.
fn matchJwt(text: []const u8, start: usize) ?usize {
    if (!std.mem.startsWith(u8, text[start..], "eyJ")) return null;
    var pos = start + runLen(text, start, isTokenBody); // header segment (includes eyJ)
    inline for (0..2) |_| {
        if (pos >= text.len or text[pos] != '.') return null;
        pos += 1;
        const seg = runLen(text, pos, isTokenBody);
        if (seg == 0) return null;
        pos += seg;
    }
    return pos;
}

/// A PEM block: `-----BEGIN` ... `-----END` ... `-----`, redacted as one unit.
fn matchPem(text: []const u8, start: usize) ?usize {
    const begin = "-----BEGIN";
    if (!std.mem.startsWith(u8, text[start..], begin)) return null;
    const end_marker = "-----END";
    const end_at = std.mem.indexOfPos(u8, text, start + begin.len, end_marker) orelse return null;
    const closing = std.mem.indexOfPos(u8, text, end_at + end_marker.len, "-----") orelse return null;
    return closing + "-----".len;
}

/// Try every built-in secret-value matcher at `text[start..]`; return the end
/// index of the longest match, or null when none match.
fn matchSecretValue(text: []const u8, start: usize) ?usize {
    var best: ?usize = null;
    inline for (.{ matchGithub, matchAws, matchAnthropic, matchJwt, matchPem }) |m| {
        if (m(text, start)) |end| {
            if (best == null or end > best.?) best = end;
        }
    }
    return best;
}

/// Redact `text` with the configured `patterns` plus the built-in secret-value
/// shapes. Each match is replaced by `marker`. Returns the rewritten text and
/// the configured patterns that matched. Fails closed when any configured
/// pattern is unsupported or malformed.
pub fn redact(arena: std.mem.Allocator, text: []const u8, patterns: []const []const u8) Error!Redacted {
    var compiled: std.ArrayList(Pattern) = .empty;
    for (patterns) |p| try compiled.append(arena, try compile(arena, p));

    var applied_flags = try arena.alloc(bool, patterns.len);
    @memset(applied_flags, false);

    var out: std.ArrayList(u8) = .empty;
    var builtin_matched = false;
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
            // No configured label matched here; redact a built-in secret value
            // shape if one starts at this position so the value itself never
            // survives into the context.
            if (matchSecretValue(text, i)) |end| {
                if (end > i) {
                    try out.appendSlice(arena, marker);
                    i = end;
                    matched = true;
                    builtin_matched = true;
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
    return .{ .text = try out.toOwnedSlice(arena), .applied = try applied.toOwnedSlice(arena), .builtin_matched = builtin_matched };
}
