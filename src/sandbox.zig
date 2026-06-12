// Layer: deterministic_core
//
// Patch sandbox: the deterministic core of copy-based mutation application
// (docs/ARCHITECTURE.md lists "applying and reverting mutations" in the
// deterministic core). `apply` validates a mutant's span and original text
// against the source buffer, then returns a patched COPY. The input `source` is
// never mutated, so the developer working tree is never changed (I-007); the
// original-text check before replacement is I-008.
//
// Filesystem workspace creation (ZNTL_SANDBOX_CREATE_FAILED, F-010) is a
// side_effect_adapter concern owned by the mutant runner, which
// combines this sandbox with the runner to create and run per-mutant
// filesystem workspaces. This module stays pure so it remains testable through
// the deterministic-core module hub.
const std = @import("std");
const mutant = @import("mutant.zig");

/// Why a patch could not be produced. Maps to invalid-ready report diagnostics.
pub const PatchError = error{
    /// Mutant span is outside source bounds (ZNTL_SANDBOX_PATCH_OUT_OF_RANGE).
    SpanOutOfRange,
    /// Source text at the span does not equal the mutant's original
    /// (ZNTL_SANDBOX_PATCH_MISMATCH).
    PatchMismatch,
};

pub const Error = PatchError || std.mem.Allocator.Error;

/// Apply one mutant to a copy of `source`, returning the patched bytes. Validates
/// the span is in range and that the source at the span matches `mutant.original`
/// before replacing. `source` is never modified.
pub fn apply(arena: std.mem.Allocator, source: []const u8, m: mutant.Mutant) Error![]u8 {
    if (m.span.byte_start > m.span.byte_end or m.span.byte_end > source.len) return error.SpanOutOfRange;
    const at_span = source[m.span.byte_start..m.span.byte_end];
    if (!std.mem.eql(u8, at_span, m.original)) return error.PatchMismatch;

    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, source[0..m.span.byte_start]);
    try out.appendSlice(arena, m.replacement);
    try out.appendSlice(arena, source[m.span.byte_end..]);
    return out.toOwnedSlice(arena);
}

/// Public ZNTL error code token for a patch failure (docs/ERROR_CODES.md).
pub fn code(err: PatchError) []const u8 {
    return switch (err) {
        error.SpanOutOfRange => "ZNTL_SANDBOX_PATCH_OUT_OF_RANGE",
        error.PatchMismatch => "ZNTL_SANDBOX_PATCH_MISMATCH",
    };
}

/// Invalid-ready failure summary for a patch failure. The `sandbox:` prefix
/// classifies the eventual mutant result as `invalid` (docs/REPORT_FORMAT.md).
pub fn failureSummary(err: PatchError) []const u8 {
    return switch (err) {
        error.SpanOutOfRange => "sandbox: mutant span is outside source bounds",
        error.PatchMismatch => "sandbox: source at span does not match mutant original text",
    };
}
