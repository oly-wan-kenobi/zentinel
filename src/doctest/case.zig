// Layer: deterministic_core
//
// Typed doctest case model and durable `dt_...` case identity
// (docs/DOCTEST_SPEC.md, docs/DOCTEST_ARCHITECTURE.md). A case is one or more
// grouped blocks (a producer plus optional secondary expectation blocks). The
// extractor (src/doctest/extractor.zig) builds these; nothing here executes
// code. Durable IDs deliberately exclude line numbers so unrelated prose edits
// do not renumber cases.
const std = @import("std");

/// Canonical case kinds for `zentinel.doctest.report.v1`. Expectation-only
/// blocks (`text output`, `json expected`, `zig after`) never produce a
/// standalone kind; they are secondary evidence on the producer case.
pub const CaseKind = enum {
    zig_compile_pass,
    zig_test,
    zig_compile_fail,
    cli,
    config,
    config_fail,
    mutation,

    pub fn toString(self: CaseKind) []const u8 {
        return @tagName(self);
    }
};

/// A grouped, typed doctest case. `id` is durable; line numbers live only in
/// `source_ref`, `block_refs`, `line_start`, and `line_end` for display.
pub const Case = struct {
    /// Durable `dt_...` id (29 bytes).
    id: []const u8,
    /// Project-relative documentation path.
    file: []const u8,
    kind: CaseKind,
    /// Explicit case label, or null when unlabeled.
    label: ?[]const u8,
    /// Anchor selector `file:line[:label]` pointing at the producer block.
    source_ref: []const u8,
    /// Every grouped block ref, producer first, then secondary blocks.
    block_refs: []const []const u8,
    /// 1-based opening line of the anchor (producer) block.
    line_start: u32,
    /// 1-based closing line of the last grouped block.
    line_end: u32,
    /// 1-based anchor line; equals `line_start` (kept explicit for selectors).
    anchor_line: u32,
};

/// Parse the 1-based anchor line out of a `file:line[:label]` source/block ref.
/// The line is the digit run after the FIRST `:`. A ref with no `:`, no digits,
/// or an out-of-range / overlong number resolves to line 0 -- which matches no
/// real 1-based anchor (so selectors yield CaseNotFound) -- rather than panicking
/// on integer overflow (Debug/ReleaseSafe) or wrapping to a wrong line
/// (ReleaseFast). This is the single shared implementation; cache.zig,
/// doctest_command.zig, and mutator_doctest.zig all call it so the four formerly
/// hand-rolled `n = n*10 + d` copies cannot drift again.
pub fn lineOfRef(ref: []const u8) u32 {
    const first = std.mem.indexOfScalar(u8, ref, ':') orelse return 0;
    var end = first + 1;
    while (end < ref.len and ref[end] >= '0' and ref[end] <= '9') : (end += 1) {}
    return std.fmt.parseInt(u32, ref[first + 1 .. end], 10) catch 0;
}

/// Parse the optional `:label` suffix out of a `file:line[:label]` ref, or null
/// when the ref carries only `file:line`. The label is everything after the
/// SECOND `:` (so a label may itself contain `:`). An empty trailing segment
/// (`file:line:`) is treated as no label.
pub fn labelOfRef(ref: []const u8) ?[]const u8 {
    const first = std.mem.indexOfScalar(u8, ref, ':') orelse return null;
    const rest = ref[first + 1 ..];
    const second = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    const label = rest[second + 1 ..];
    return if (label.len == 0) null else label;
}

/// Lowercase Crockford base32 alphabet (excludes i, l, o, u). Matches src/mutant.zig.
const crockford_lower = "0123456789abcdefghjkmnpqrstvwxyz";

/// Durable doctest case id length: `dt_` plus 26 base32 characters.
pub const id_len = 29;

const id_namespace = "zentinel.doctest_case.v1";

/// Durable-id inputs (docs/DOCTEST_SPEC.md "Case Identity"): project-relative
/// path, case kind, explicit label when present, normalized block grouping
/// metadata, and a content hash of the grouped blocks. Line numbers are never
/// inputs.
pub const Identity = struct {
    file: []const u8,
    kind: CaseKind,
    /// Explicit label, or "" when unlabeled.
    label: []const u8,
    /// Normalized block grouping metadata (e.g. `cli:none;output:contains`).
    grouping: []const u8,
    /// Hex SHA-256 over the grouped block contents.
    content_hash: []const u8,
};

/// `dt_ + first_26(lowercase_unpadded_crockford_base32(sha256(canonical_bytes)))`
/// where `canonical_bytes` is the UTF-8, `\n`-separated identity fields in the
/// documented order. Byte-identical across machines for the same fields.
pub fn computeId(id: Identity) [id_len]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(id_namespace);
    hasher.update("\n");
    hasher.update(id.file);
    hasher.update("\n");
    hasher.update(id.kind.toString());
    hasher.update("\n");
    hasher.update(id.label);
    hasher.update("\n");
    hasher.update(id.grouping);
    hasher.update("\n");
    hasher.update(id.content_hash);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var out: [id_len]u8 = undefined;
    out[0] = 'd';
    out[1] = 't';
    out[2] = '_';
    // MSB-first 5-bit packing of the digest into 26 base32 symbols.
    var bits: u32 = 0;
    var nbits: u8 = 0;
    var di: usize = 0;
    var oi: usize = 3;
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
