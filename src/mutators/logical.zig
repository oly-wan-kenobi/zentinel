// Layer: deterministic_core
//
// Logical AST mutator (docs/MUTATOR_SPEC.md): `logical_and_or` swaps the
// short-circuit boolean keywords `and`<->`or` on `.bool_and`/`.bool_or` nodes.
// Bitwise `&`/`|` and unary `!` are not these node tags and are never
// recognized. Pure: emits candidates through the shared collector.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator = "logical_and_or";

const risks = [_][]const u8{
    "one operand constant",
    "guards where later code makes branches equivalent",
    "tests not covering short-circuit side effects",
};

fn replacementFor(tag: std.zig.Ast.Node.Tag) ?[]const u8 {
    return switch (tag) {
        .bool_and => "or",
        .bool_or => "and",
        else => null,
    };
}

pub fn collect(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
) std.mem.Allocator.Error!void {
    const node_tags = parsed.tree.nodes.items(.tag);
    for (node_tags, 0..) |tag, i| {
        const replacement = replacementFor(tag) orelse continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        const op_tok = parsed.tree.nodeMainToken(node);
        const op_start = parsed.tree.tokenStart(op_tok);
        if (ast_backend.inTestBody(test_ranges, op_start)) continue;
        const op_text = parsed.tree.tokenSlice(op_tok);
        const op_end = op_start + @as(u32, @intCast(op_text.len));
        const start_pos = source_map.locate(parsed.tree.source, op_start) orelse continue;
        const end_pos = source_map.locate(parsed.tree.source, op_end) orelse continue;
        try collector.add(.{
            .id = "",
            .backend = .ast,
            .backend_version = mutant.ast_backend_version,
            .backend_stability = .stable,
            .operator = operator,
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
            .replacement = replacement,
            .expected_compile = .compiles,
            .equivalent_risks = &risks,
        });
    }
}
