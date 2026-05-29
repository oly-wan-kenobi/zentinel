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

pub const Backend = enum { ast, zir, air };
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
};

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
