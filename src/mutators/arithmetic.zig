// Layer: deterministic_core
//
// Arithmetic AST mutators (docs/MUTATOR_SPEC.md): `arithmetic_add_sub` swaps
// `+`<->`-` and `arithmetic_mul_div` swaps `*`<->`/` on binary numeric
// expressions. Recognizes only the non-wrapping, non-saturating binary operator
// nodes; unary negation and wrapping operators are ignored. Compound-assignment
// operators (`+=`, `-=`, `*=`, `/=`) are out of scope for v1 and are not mutated
// -- a documented boundary, not an oversight (docs/MUTATOR_SPEC.md forbidden
// contexts). Pure: emits candidates through the shared collector and never
// patches or runs anything.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator_add_sub = "arithmetic_add_sub";
pub const operator_mul_div = "arithmetic_mul_div";

const Swap = struct { operator: []const u8, replacement: []const u8 };

fn swapFor(tag: std.zig.Ast.Node.Tag) ?Swap {
    return switch (tag) {
        .add => .{ .operator = operator_add_sub, .replacement = "-" },
        .sub => .{ .operator = operator_add_sub, .replacement = "+" },
        .mul => .{ .operator = operator_mul_div, .replacement = "/" },
        .div => .{ .operator = operator_mul_div, .replacement = "*" },
        // `.add_wrap`/`.sub_wrap`/`.mul_wrap`/`.*_sat`, unary `.negation`, and
        // compound assignment (`.assign_add`/`.assign_sub`/`.assign_mul`/
        // `.assign_div`, i.e. `+=`/`-=`/`*=`/`/=`) are intentionally excluded
        // (MUTATOR_SPEC forbidden contexts): v1 mutates only binary arithmetic
        // operator expressions.
        else => null,
    };
}

/// Recognize arithmetic binary operators in `parsed` and append swap candidates
/// to `collector`, skipping operators inside the given test-declaration ranges.
/// Expected compile is `may_fail`: without type information the AST layer cannot
/// prove an unsigned/comptime-negative swap compiles, so a compile-error mutant
/// is a documented expected outcome rather than an invalid candidate.
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
            .expected_compile = .may_fail,
        });
    }
}
