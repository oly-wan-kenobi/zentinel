// Layer: deterministic_core
//
// Durable mutation-aware doctest identities (docs/DOCTEST_SPEC.md "Doctest
// Mutation Entry IDs" and "Doctest Survivor Refs"). A `dm_...` id is the durable
// id of one `case.kind = "mutation"` report entry; a `ds_...` ref is the durable
// selector for a survived documentation mutant. Both are
// `<prefix> + first_26(lowercase_unpadded_crockford_base32(sha256(canonical_bytes)))`
// over the same field set in the documented order, differing only by the
// schema-version namespace line. Pure: no execution, no wall-clock, no display
// order, no command output.
const std = @import("std");

/// `<prefix>` (3 bytes incl. `_`) plus 26 base32 characters.
pub const id_len = 29;

const crockford_lower = "0123456789abcdefghjkmnpqrstvwxyz";

pub const mutation_case_namespace = "zentinel.doctest_mutation_case.v1";
pub const survivor_namespace = "zentinel.doctest_survivor.v1";

/// The exact, ordered identity inputs shared by `dm_` and `ds_` derivation.
/// `normalized_mutated_diff` must already be normalized (project-relative `/`
/// paths, trailing whitespace stripped per line, `\n` separators).
pub const Identity = struct {
    doctest_case_id: []const u8,
    mutant_id: []const u8,
    operator: []const u8,
    doc_file: []const u8,
    source_ref: []const u8,
    normalized_mutated_diff: []const u8,
};

fn derive(prefix: []const u8, namespace: []const u8, id: Identity) [id_len]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(namespace);
    hasher.update("\n");
    hasher.update(id.doctest_case_id);
    hasher.update("\n");
    hasher.update(id.mutant_id);
    hasher.update("\n");
    hasher.update(id.operator);
    hasher.update("\n");
    hasher.update(id.doc_file);
    hasher.update("\n");
    hasher.update(id.source_ref);
    hasher.update("\n");
    hasher.update(id.normalized_mutated_diff);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var out: [id_len]u8 = undefined;
    out[0] = prefix[0];
    out[1] = prefix[1];
    out[2] = prefix[2];
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

/// Durable `dm_...` id for a `case.kind = "mutation"` report entry.
pub fn mutationCaseId(id: Identity) [id_len]u8 {
    return derive("dm_", mutation_case_namespace, id);
}

/// Durable `ds_...` survivor ref. Emitted only for survived documentation
/// mutants; the caller passes `null` for every other status.
pub fn survivorRef(id: Identity) [id_len]u8 {
    return derive("ds_", survivor_namespace, id);
}

/// Normalize a mutated diff for hashing and storage: each line has trailing
/// whitespace stripped, lines are joined with `\n`. Project-relative `/`
/// separators are assumed (diff lines come from project-relative source).
pub fn normalizeDiff(arena: std.mem.Allocator, diff: []const []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (diff, 0..) |line, i| {
        if (i > 0) try out.append(arena, '\n');
        const trimmed = std.mem.trimEnd(u8, line, " \t\r");
        try out.appendSlice(arena, trimmed);
    }
    return out.toOwnedSlice(arena);
}
