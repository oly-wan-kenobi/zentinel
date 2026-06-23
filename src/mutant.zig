// Layer: deterministic_core
//
// Shared mutant model used by every backend and the report (docs/ARCHITECTURE.md,
// docs/INTERNAL_API_CONTRACTS.md). Owns the durable `m_...` identity algorithm,
// source spans, and the structural invalid-candidate contract. Pure: no
// candidate generation, patching, or execution. Identity is independent of
// display order, timing, results, or AI output.
const std = @import("std");

/// Identity namespace prefix mixed into every durable id (docs/ARCHITECTURE.md).
pub const id_namespace = "zentinel.mutant.v1";

/// The internal deterministic backend contract string for the stable AST
/// backend under Zig 0.16.0. Participates in durable identity and cache keys but
/// is intentionally absent from report v1 public entries.
pub const ast_backend_version = "ast.v1.zig-0.16.0";

pub const Backend = enum { ast, zir };
pub const BackendStability = enum { stable, experimental };
pub const OperatorStability = enum { stable, preview, experimental };
pub const ExpectedCompile = enum { compiles, may_fail, must_fail };

pub const Span = struct {
    byte_start: u64,
    byte_end: u64,
    line_start: u32,
    column_start: u32,
    line_end: u32,
    column_end: u32,

    /// Byte offsets are authoritative; line/column are 1-based. A valid span has
    /// `byte_start <= byte_end <= source_len` and non-zero, non-decreasing lines.
    pub fn isValid(self: Span, source_len: usize) bool {
        if (self.byte_start > self.byte_end) return false;
        if (self.byte_end > source_len) return false;
        if (self.line_start == 0 or self.column_start == 0 or self.line_end == 0 or self.column_end == 0) return false;
        if (self.line_end < self.line_start) return false;
        return true;
    }

    pub fn len(self: Span) u64 {
        return self.byte_end - self.byte_start;
    }
};

/// The exact, ordered field set that determines durable identity.
pub const Identity = struct {
    backend_version: []const u8,
    file: []const u8,
    operator: []const u8,
    span_start: u64,
    span_end: u64,
    original: []const u8,
    replacement: []const u8,
};

/// The shared mutant model. `id` is derived from `identity()` by `computeId`;
/// the report adds a display index and per-mutant result that are not part of
/// durable identity.
pub const Mutant = struct {
    id: []const u8,
    backend: Backend,
    backend_version: []const u8,
    backend_stability: BackendStability,
    operator: []const u8,
    operator_stability: OperatorStability,
    file: []const u8,
    span: Span,
    original: []const u8,
    replacement: []const u8,
    expected_compile: ExpectedCompile,
    equivalent_risks: []const []const u8 = &.{},

    pub fn identity(self: Mutant) Identity {
        return .{
            .backend_version = self.backend_version,
            .file = self.file,
            .operator = self.operator,
            .span_start = self.span.byte_start,
            .span_end = self.span.byte_end,
            .original = self.original,
            .replacement = self.replacement,
        };
    }

    /// Structural invalid-candidate contract (I-011, F-009, ZNTL_MUTATOR_INVALID_CANDIDATE):
    /// the span must be well-formed and cover exactly the original text, and the
    /// replacement must actually change the source. Verifying that `original`
    /// matches the real source buffer at the span is the sandbox's job.
    pub fn isValidCandidate(self: Mutant, source_len: usize) bool {
        if (!self.span.isValid(source_len)) return false;
        if (self.span.len() != self.original.len) return false;
        if (std.mem.eql(u8, self.original, self.replacement)) return false;
        return true;
    }

    /// Source-length-independent candidate shape check used by collectors before
    /// a full source buffer is available to the sandbox. The sandbox still owns
    /// the authoritative span/source match validation.
    pub fn hasValidEditShape(self: Mutant) bool {
        if (self.span.byte_start > self.span.byte_end) return false;
        if (self.span.line_start == 0 or self.span.column_start == 0 or self.span.line_end == 0 or self.span.column_end == 0) return false;
        if (self.span.line_end < self.span.line_start) return false;
        if (self.span.len() != self.original.len) return false;
        if (std.mem.eql(u8, self.original, self.replacement)) return false;
        return true;
    }
};

fn isMutantSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

/// True when `a` equals `b` ignoring ALL whitespace bytes in either.
fn eqlIgnoringWhitespace(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < a.len and isMutantSpace(a[i])) i += 1;
        while (j < b.len and isMutantSpace(b[j])) j += 1;
        if (i >= a.len or j >= b.len) return i >= a.len and j >= b.len;
        if (a[i] != b[j]) return false;
        i += 1;
        j += 1;
    }
}

/// Strip a matched pair of outer parentheses that wraps the WHOLE expression
/// (e.g. `(unreachable)` -> `unreachable`), repeatedly; leaves `(a) + (b)` alone.
fn stripWrappingParens(s: []const u8) []const u8 {
    var t = std.mem.trim(u8, s, " \t\r\n");
    while (t.len >= 2 and t[0] == '(' and t[t.len - 1] == ')') {
        var depth: usize = 0;
        var wraps_whole = false;
        for (t, 0..) |c, idx| {
            if (c == '(') {
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
                if (depth == 0) {
                    wraps_whole = idx == t.len - 1;
                    break;
                }
            }
        }
        if (!wraps_whole) break;
        t = std.mem.trim(u8, t[1 .. t.len - 1], " \t\r\n");
    }
    return t;
}

/// Whether `original` is already semantically `canonical` -- ignoring surrounding
/// whitespace, a wrapping paren pair, and all interior whitespace. Phase-2
/// mutators use this to skip re-mutating non-canonically-spelled source (e.g.
/// `errdefer  {}`, `catch (unreachable)`, `orelse (unreachable)`) that would
/// otherwise emit a pure-formatting no-op -- a guaranteed-equivalent survivor
/// that pollutes the surviving set and depresses the mutation score.
pub fn equivalentToCanonical(original: []const u8, canonical: []const u8) bool {
    return eqlIgnoringWhitespace(stripWrappingParens(original), canonical);
}

/// Lowercase Crockford base32 alphabet (excludes i, l, o, u).
const crockford_lower = "0123456789abcdefghjkmnpqrstvwxyz";

/// Length of a durable id: `m_` plus 26 base32 characters.
pub const id_len = 28;

/// Derive the durable `m_...` id:
/// `m_ + first_26(lowercase_unpadded_crockford_base32(sha256(canonical_bytes)))`
/// where `canonical_bytes` is the UTF-8, `\n`-separated identity fields in the
/// documented order. Byte-identical across machines for the same fields.
pub fn computeId(id: Identity) [id_len]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(id_namespace);
    hasher.update("\n");
    hasher.update(id.backend_version);
    hasher.update("\n");
    hasher.update(id.file);
    hasher.update("\n");
    hasher.update(id.operator);
    hasher.update("\n");
    var numbuf: [20]u8 = undefined;
    hasher.update(std.fmt.bufPrint(&numbuf, "{d}", .{id.span_start}) catch unreachable);
    hasher.update("\n");
    hasher.update(std.fmt.bufPrint(&numbuf, "{d}", .{id.span_end}) catch unreachable);
    hasher.update("\n");
    hasher.update(id.original);
    hasher.update("\n");
    hasher.update(id.replacement);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var out: [id_len]u8 = undefined;
    out[0] = 'm';
    out[1] = '_';
    // MSB-first 5-bit packing of the digest into 26 base32 symbols.
    var bits: u32 = 0;
    var nbits: u8 = 0;
    var di: usize = 0;
    var oi: usize = 2;
    while (oi < id_len) : (oi += 1) {
        if (nbits < 5) {
            bits = (bits << 8) | digest[di];
            di += 1;
            nbits += 8;
        }
        nbits -= 5;
        out[oi] = crockford_lower[(bits >> @intCast(nbits)) & 0x1f];
    }
    return out;
}

/// Canonical candidate ordering: file, byte start, byte end, operator,
/// replacement, backend (docs/MUTATOR_SPEC.md, docs/REPORT_FORMAT.md).
pub fn lessThan(_: void, a: Mutant, b: Mutant) bool {
    switch (std.mem.order(u8, a.file, b.file)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    if (a.span.byte_start != b.span.byte_start) return a.span.byte_start < b.span.byte_start;
    if (a.span.byte_end != b.span.byte_end) return a.span.byte_end < b.span.byte_end;
    switch (std.mem.order(u8, a.operator, b.operator)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    switch (std.mem.order(u8, a.replacement, b.replacement)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    return @intFromEnum(a.backend) < @intFromEnum(b.backend);
}

/// Sort mutants into canonical order. Display indices are assigned by the report
/// after sorting and are not part of identity.
pub fn sort(mutants: []Mutant) void {
    std.mem.sort(Mutant, mutants, {}, lessThan);
}

/// True when two candidates produce the same physical edit, regardless of which
/// operator recognized it. The first candidate in canonical order is retained.
pub fn samePhysicalEdit(a: Mutant, b: Mutant) bool {
    return std.mem.eql(u8, a.file, b.file) and
        a.span.byte_start == b.span.byte_start and
        a.span.byte_end == b.span.byte_end and
        std.mem.eql(u8, a.original, b.original) and
        std.mem.eql(u8, a.replacement, b.replacement);
}

/// Compute the durable id from `m.identity()` and store it in `m.id`, allocating
/// the id bytes into `arena`.
pub fn assignId(arena: std.mem.Allocator, m: *Mutant) std.mem.Allocator.Error!void {
    const id = computeId(m.identity());
    m.id = try arena.dupe(u8, &id);
}

/// Return a canonically-sorted copy of `mutants` with exact-identity duplicates
/// and duplicate physical edits removed. Ids must already be assigned. When two
/// operators recognize the same edit, the first candidate in canonical order is
/// retained so the representative is deterministic.
pub fn sortAndDedupe(arena: std.mem.Allocator, mutants: []const Mutant) std.mem.Allocator.Error![]Mutant {
    const copy = try arena.dupe(Mutant, mutants);
    sort(copy);
    // Hash-set dedupe instead of a nested scan of the kept list: cross-operator
    // physical-edit duplicates are not guaranteed adjacent after the sort (operator
    // sorts between byte_end and replacement), so an adjacent-only pass is unsound,
    // and the old growing-list scan was O(K^2) in the candidate count. Iterating
    // `copy` in canonical order keeps the first occurrence as the representative.
    var seen_id = std.StringHashMap(void).init(arena);
    defer seen_id.deinit();
    var seen_edit = std.StringHashMap(void).init(arena);
    defer seen_edit.deinit();
    var out: std.ArrayList(Mutant) = .empty;
    for (copy) |m| {
        // Cheap exact-identity check first: an `m_...` id repeat is a duplicate
        // regardless of content, so skip building the (allocated) edit_key for it.
        if (seen_id.contains(m.id)) continue;
        const edit_key = try std.fmt.allocPrint(arena, "{s}\x00{d}\x00{d}\x00{s}\x00{s}", .{ m.file, m.span.byte_start, m.span.byte_end, m.original, m.replacement });
        if (seen_edit.contains(edit_key)) continue;
        try seen_id.put(m.id, {});
        try seen_edit.put(edit_key, {});
        try out.append(arena, m);
    }
    return out.toOwnedSlice(arena);
}
