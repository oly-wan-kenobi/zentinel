const std = @import("std");
const zentinel = @import("zentinel");
const mutant = zentinel.mutant;
const report = zentinel.report;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// Pinned vector, computed independently (sha256 of the canonical `\n`-separated
// field bytes -> lowercase unpadded Crockford base32 -> first 26 chars). If the
// hash, encoding, or truncation drift, this must change.
const vector_identity = mutant.Identity{
    .backend_version = "ast.v1.zig-0.16.0",
    .file = "src/range.zig",
    .operator = "comparison_boundary",
    .span_start = 310,
    .span_end = 312,
    .original = ">=",
    .replacement = ">",
};
const expected_id = "m_8kjyy9kdjw9zngpb31q659cqmt";

const sample_span = mutant.Span{ .byte_start = 310, .byte_end = 312, .line_start = 12, .column_start = 13, .line_end = 12, .column_end = 15 };

const sample = mutant.Mutant{
    .id = "m_placeholder",
    .backend = .ast,
    .backend_version = mutant.ast_backend_version,
    .backend_stability = .stable,
    .operator = "comparison_boundary",
    .operator_stability = .stable,
    .file = "src/range.zig",
    .span = sample_span,
    .original = ">=",
    .replacement = ">",
    .expected_compile = .compiles,
};

test "computeId matches the documented m_ derivation and the pinned vector" {
    const id = mutant.computeId(vector_identity);
    try expectEqualStrings(expected_id, &id);
    // The shared model derives the same identity from a full Mutant value.
    try expectEqualStrings(expected_id, &mutant.computeId(sample.identity()));
}

test "durable id matches ^m_[A-Za-z0-9]+$" {
    const id = mutant.computeId(vector_identity);
    try expect(std.mem.startsWith(u8, &id, "m_"));
    try expect(id.len == 28);
    for (id[2..]) |c| try expect(std.ascii.isAlphanumeric(c));
}

test "backend_version participates in durable identity" {
    var other = vector_identity;
    other.backend_version = "ast.v1.zig-0.99.9";
    const a = mutant.computeId(vector_identity);
    const b = mutant.computeId(other);
    try expect(!std.mem.eql(u8, &a, &b));
}

test "identity ignores fields outside the canonical set" {
    // Two mutants with identical identity fields but different display/stability
    // metadata produce the same durable id.
    var m1 = sample;
    m1.backend_stability = .stable;
    var m2 = sample;
    m2.operator_stability = .preview;
    try expectEqualStrings(&mutant.computeId(m1.identity()), &mutant.computeId(m2.identity()));
}

test "mutants sort by file, byte span, operator, replacement, backend" {
    const a = sample; // src/range.zig, 310..312, comparison_boundary, ">"
    var b = sample;
    b.file = "src/aaa.zig";
    var c = sample;
    c.span.byte_start = 100;
    c.span.byte_end = 102;
    var d = sample;
    d.replacement = ">=stuff"; // same file/span/operator as a, later replacement
    var arr = [_]mutant.Mutant{ a, d, c, b };
    mutant.sort(&arr);
    // src/aaa.zig sorts before src/range.zig; within src/range.zig, byte_start
    // 100 (c) precedes 310; among byte 310 entries, replacement ">" before ">=stuff".
    try expectEqualStrings("src/aaa.zig", arr[0].file);
    try expectEqual(@as(u64, 100), arr[1].span.byte_start);
    try expectEqualStrings(">", arr[2].replacement);
    try expectEqualStrings(">=stuff", arr[3].replacement);
}

test "source span validation rejects malformed spans" {
    try expect(sample_span.isValid(1000));
    var reversed = sample_span;
    reversed.byte_start = 400; // start > end
    try expect(!reversed.isValid(1000));
    var out_of_range = sample_span;
    out_of_range.byte_end = 2000; // beyond source length
    try expect(!out_of_range.isValid(1000));
    var zero_line = sample_span;
    zero_line.line_start = 0; // 1-based
    try expect(!zero_line.isValid(1000));
}

test "invalid candidate contract rejects malformed mutants" {
    const src_len: usize = 1000;
    try expect(sample.isValidCandidate(src_len));

    var wrong_len = sample;
    wrong_len.original = ">"; // span length 2 but original length 1
    try expect(!wrong_len.isValidCandidate(src_len));

    var out_of_range = sample;
    out_of_range.span.byte_end = src_len + 5;
    try expect(!out_of_range.isValidCandidate(src_len));

    var no_op = sample;
    no_op.replacement = ">="; // identical to original is not a mutation
    try expect(!no_op.isValidCandidate(src_len));
}

test "report serialization consumes the shared model types without duplicating them" {
    try expect(report.Span == mutant.Span);
    try expect(report.Backend == mutant.Backend);
    try expect(report.ExpectedCompile == mutant.ExpectedCompile);
    try expect(report.BackendStability == mutant.BackendStability);
    try expect(report.OperatorStability == mutant.OperatorStability);
}
