// Layer: deterministic_core
//
// Error-path AST mutator (docs/MUTATOR_SPEC.md, Phase 2):
//   `error_catch_unreachable`: `expr catch handler` -> `expr catch unreachable`
// The candidate span is the exact catch handler expression (the `catch`
// right-hand side); for a `catch |err| handler` form only the handler is
// replaced, never the `|err|` capture. Pure: emits candidates through the shared
// collector; no patching or execution.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator = "error_catch_unreachable";

const risks = [_][]const u8{
    "error path never exercised",
    "handler already terminates",
};

pub fn collect(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
) std.mem.Allocator.Error!void {
    const tree = parsed.tree;
    const node_tags = tree.nodes.items(.tag);
    for (node_tags, 0..) |tag, i| {
        if (tag != .@"catch") continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        const handler = tree.nodeData(node).node_and_node[1]; // catch right-hand side
        const first = tree.firstToken(handler);
        const last = tree.lastToken(handler);
        const start = tree.tokenStart(first);
        const last_slice = tree.tokenSlice(last);
        const end = tree.tokenStart(last) + @as(u32, @intCast(last_slice.len));
        if (ast_backend.inTestBody(test_ranges, start)) continue;
        const original = tree.source[start..end];
        // An existing `catch unreachable` is a forbidden context.
        if (std.mem.eql(u8, original, "unreachable")) continue;
        const start_pos = source_map.locate(tree.source, start) orelse continue;
        const end_pos = source_map.locate(tree.source, end) orelse continue;
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
            .original = original,
            .replacement = "unreachable",
            .expected_compile = .may_fail,
            .equivalent_risks = &risks,
        });
    }
}
