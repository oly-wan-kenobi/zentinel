// Layer: deterministic_core
//
// Boolean literal AST mutator (docs/MUTATOR_SPEC.md): `boolean_literal` swaps
// `true`<->`false`. In Zig `true`/`false` are identifier expressions, so this
// recognizes `.identifier` nodes whose token text is exactly `true`/`false`.
// That excludes enum literals like `.true` (a different node tag) and literals
// inside comments or strings (which are not identifier nodes). Pure: emits
// candidates through the shared collector.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator = "boolean_literal";

const risks = [_][]const u8{
    "literal used in dead code",
    "literal overwritten before observation",
};

fn replacementFor(text: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, text, "true")) return "false";
    if (std.mem.eql(u8, text, "false")) return "true";
    return null;
}

pub fn collect(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
) std.mem.Allocator.Error!void {
    const node_tags = parsed.tree.nodes.items(.tag);
    for (node_tags, 0..) |tag, i| {
        if (tag != .identifier) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        const tok = parsed.tree.nodeMainToken(node);
        const text = parsed.tree.tokenSlice(tok);
        const replacement = replacementFor(text) orelse continue;
        const start = parsed.tree.tokenStart(tok);
        if (ast_backend.inTestBody(test_ranges, start)) continue;
        const end = start + @as(u32, @intCast(text.len));
        const start_pos = source_map.locate(parsed.tree.source, start) orelse continue;
        const end_pos = source_map.locate(parsed.tree.source, end) orelse continue;
        try collector.add(.{
            .id = "",
            .backend = .ast,
            .backend_version = mutant.ast_backend_version,
            .backend_stability = .stable,
            .operator = operator,
            .operator_stability = .stable,
            .file = file,
            .span = .{
                .byte_start = start,
                .byte_end = end,
                .line_start = start_pos.line,
                .column_start = start_pos.column,
                .line_end = end_pos.line,
                .column_end = end_pos.column,
            },
            .original = text,
            .replacement = replacement,
            .expected_compile = .compiles,
            .equivalent_risks = &risks,
        });
    }
}
