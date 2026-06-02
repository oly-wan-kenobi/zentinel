// Layer: deterministic_core
//
// Integer literal boundary AST mutator (docs/MUTATOR_SPEC.md, Phase 2):
//   `integer_literal_boundary`: an integer literal used in a branch/length-check
//   comparison gets paired `+1` and `-1` boundary replacements.
// Allowlist by context: only literals that are direct operands of a comparison
// (`==`, `!=`, `<`, `<=`, `>`, `>=`) are mutated, so protected literals in
// declarations, enum tags, array lengths, and `align(...)` are naturally left
// alone. Only plain decimal literals are mutated (syntax-local; hex/binary/octal
// and underscore/suffix forms are skipped). Compile expectation is `may_fail`
// because a +/-1 can overflow the operand's integer type. Pure: emits candidates
// through the shared collector; no patching or execution.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator = "integer_literal_boundary";

const risks = [_][]const u8{
    "boundary values untested",
    "literal is not semantically a boundary",
};

fn isComparison(tag: std.zig.Ast.Node.Tag) bool {
    return switch (tag) {
        .equal_equal, .bang_equal, .less_than, .less_or_equal, .greater_than, .greater_or_equal => true,
        else => false,
    };
}

fn isPlainDecimal(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |ch| if (ch < '0' or ch > '9') return false;
    return true;
}

pub fn collect(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
) std.mem.Allocator.Error!void {
    const tree = parsed.tree;
    const node_tags = tree.nodes.items(.tag);
    for (node_tags, 0..) |tag, i| {
        if (!isComparison(tag)) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        const operands = tree.nodeData(node).node_and_node;
        try emitForOperand(collector, parsed, file, test_ranges, node_tags, operands[0]);
        try emitForOperand(collector, parsed, file, test_ranges, node_tags, operands[1]);
    }
}

fn emitForOperand(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
    node_tags: []const std.zig.Ast.Node.Tag,
    operand: std.zig.Ast.Node.Index,
) std.mem.Allocator.Error!void {
    const idx = @intFromEnum(operand);
    if (idx >= node_tags.len or node_tags[idx] != .number_literal) return;
    const tree = parsed.tree;
    const tok = tree.nodeMainToken(operand);
    const start = tree.tokenStart(tok);
    if (ast_backend.inTestBody(test_ranges, start)) return;
    const text = tree.tokenSlice(tok);
    if (!isPlainDecimal(text)) return;
    const value = std.fmt.parseInt(i128, text, 10) catch return;
    const end = start + @as(u32, @intCast(text.len));
    const start_pos = source_map.locate(tree.source, start) orelse return;
    const end_pos = source_map.locate(tree.source, end) orelse return;
    const span: mutant.Span = .{
        .byte_start = start,
        .byte_end = end,
        .line_start = start_pos.line,
        .column_start = start_pos.column,
        .line_end = end_pos.line,
        .column_end = end_pos.column,
    };
    // Guard the boundary arithmetic against i128 overflow: a +/-1 boundary that is
    // unrepresentable in i128 (the literal sitting at i128's own max/min) is not a
    // meaningful mutant, so skip just that boundary. Computing it unchecked would
    // be a checked illegal behavior -> `panic: integer overflow` that a `catch`
    // cannot intercept, aborting the whole in-process candidate pass (H1).
    if (std.math.add(i128, value, 1)) |plus| {
        try emit(collector, file, span, text, try std.fmt.allocPrint(collector.allocator, "{d}", .{plus}));
    } else |_| {}
    if (std.math.sub(i128, value, 1)) |minus| {
        try emit(collector, file, span, text, try std.fmt.allocPrint(collector.allocator, "{d}", .{minus}));
    } else |_| {}
}

fn emit(
    collector: *ast_backend.Collector,
    file: []const u8,
    span: mutant.Span,
    original: []const u8,
    replacement: []const u8,
) std.mem.Allocator.Error!void {
    try collector.add(.{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = operator,
        .operator_stability = .stable,
        .file = file,
        .span = span,
        .original = original,
        .replacement = replacement,
        .expected_compile = .may_fail,
        .equivalent_risks = &risks,
    });
}
