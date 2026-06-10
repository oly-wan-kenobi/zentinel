// Layer: deterministic_core
//
// Comparison AST mutators (docs/MUTATOR_SPEC.md): `equality_swap` swaps
// `==`<->`!=` and `comparison_boundary` swaps the inclusive/exclusive boundary
// (`<`<->`<=`, `>`<->`>=`). Operators inside comments or string literals are not
// AST comparison nodes, so they are naturally never recognized. Equality
// comparisons against the `null` literal are reserved for `optional_null_check`.
// Pure: emits candidates through the shared collector; no patching or execution.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator_equality = "equality_swap";
pub const operator_boundary = "comparison_boundary";

// Equivalent-risk hints carried from MUTATOR_SPEC onto candidate metadata.
const equality_risks = [_][]const u8{
    "values known to differ in all tests",
    "dead branches",
    "comparisons guarded by identical previous checks",
};
const boundary_risks = [_][]const u8{
    "missing exact-boundary inputs",
    "floating-point NaN behavior",
    "values constrained away from boundary",
};

const Swap = struct {
    operator: []const u8,
    replacement: []const u8,
    risks: []const []const u8,
};

fn swapFor(tag: std.zig.Ast.Node.Tag) ?Swap {
    return switch (tag) {
        .equal_equal => .{ .operator = operator_equality, .replacement = "!=", .risks = &equality_risks },
        .bang_equal => .{ .operator = operator_equality, .replacement = "==", .risks = &equality_risks },
        .less_than => .{ .operator = operator_boundary, .replacement = "<=", .risks = &boundary_risks },
        .less_or_equal => .{ .operator = operator_boundary, .replacement = "<", .risks = &boundary_risks },
        .greater_than => .{ .operator = operator_boundary, .replacement = ">=", .risks = &boundary_risks },
        .greater_or_equal => .{ .operator = operator_boundary, .replacement = ">", .risks = &boundary_risks },
        else => null,
    };
}

/// True if the token at `tok` is the `null` literal. Used to leave `x == null`
/// and `x != null` to `optional_null_check` (MUTATOR_SPEC forbidden context).
fn isNullToken(parsed: ast_backend.Parsed, tok: u32) bool {
    if (tok >= parsed.tree.tokens.len) return false;
    return std.mem.eql(u8, parsed.tree.tokenSlice(tok), "null");
}

pub fn collect(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
) std.mem.Allocator.Error!void {
    const node_tags = parsed.tree.nodes.items(.tag);
    const li = try source_map.LineIndex.init(collector.allocator, parsed.tree.source);
    for (node_tags, 0..) |tag, i| {
        const swap = swapFor(tag) orelse continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        const op_tok = parsed.tree.nodeMainToken(node);
        const op_start = parsed.tree.tokenStart(op_tok);
        if (ast_backend.inTestBody(test_ranges, op_start)) continue;
        // Equality comparisons against `null` belong to optional_null_check.
        if (std.mem.eql(u8, swap.operator, operator_equality)) {
            const right_is_null = isNullToken(parsed, op_tok + 1);
            const left_is_null = op_tok > 0 and isNullToken(parsed, op_tok - 1);
            if (right_is_null or left_is_null) continue;
        }
        const op_text = parsed.tree.tokenSlice(op_tok);
        const op_end = op_start + @as(u32, @intCast(op_text.len));
        const start_pos = li.locate(op_start) orelse continue;
        const end_pos = li.locate(op_end) orelse continue;
        try collector.add(.{
            .id = "",
            .backend = .ast,
            .backend_version = mutant.ast_backend_version,
            .backend_stability = .stable,
            .operator = swap.operator,
            .operator_stability = .stable,
            .file = file,
            .span = .{
                .byte_start = op_start,
                .byte_end = op_end,
                .line_start = start_pos.line,
                .column_start = start_pos.column,
                .line_end = end_pos.line,
                .column_end = end_pos.column,
            },
            .original = op_text,
            .replacement = swap.replacement,
            .expected_compile = .compiles,
            .equivalent_risks = swap.risks,
        });
    }
}
