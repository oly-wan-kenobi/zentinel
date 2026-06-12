// Layer: deterministic_core
//
// Boolean literal AST mutator (docs/MUTATOR_SPEC.md): `boolean_literal` swaps
// `true`<->`false`. In Zig `true`/`false` are identifier expressions, so this
// recognizes `.identifier` nodes whose token text is exactly `true`/`false`.
// That excludes enum literals like `.true` (a `field_access` node) and literals
// inside comments or strings (which are not identifier nodes). It ALSO skips an
// enum field DECLARATION named `true`/`false` (e.g. `enum { true, false }`):
// MUTATOR_SPEC.md forbids mutating field names, and such a member parses as a
// tuple-like `container_field_*` whose `type_expr` is the `true`/`false`
// identifier -- mutating it would emit `enum { false, false }`, a guaranteed
// `duplicate enum member name` compile_error rather than a real boolean swap
//. Pure: emits candidates through the shared collector.
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

/// Collect the `type_expr` node of every tuple-like container field in the tree
/// (the nodes that are field NAMES, not boolean VALUES). A value-less member like
/// `enum { true, false }` parses as a tuple-like `container_field_*` whose
/// `type_expr` IS the `true`/`false` identifier; mutating it is forbidden
/// (MUTATOR_SPEC.md) and yields a guaranteed `duplicate member` compile_error
///. Computed ONCE per `collect` so the per-literal skip check is O(1)
/// amortized rather than rescanning every node for each literal (O(n^2)). These
/// fields are rare, so the list is usually empty. A boolean value is never a
/// container-field type expression, so this never lists a real literal.
fn containerFieldNameNodes(
    alloc: std.mem.Allocator,
    tree: std.zig.Ast,
) std.mem.Allocator.Error![]const std.zig.Ast.Node.Index {
    var list: std.ArrayList(std.zig.Ast.Node.Index) = .empty;
    const tags = tree.nodes.items(.tag);
    for (tags, 0..) |tag, i| switch (tag) {
        .container_field, .container_field_init, .container_field_align => {
            const cf = tree.fullContainerField(@enumFromInt(@as(u32, @intCast(i)))) orelse continue;
            if (cf.ast.tuple_like) {
                if (cf.ast.type_expr.unwrap()) |te| try list.append(alloc, te);
            }
        },
        else => {},
    };
    return list.toOwnedSlice(alloc);
}

fn nodeInList(nodes: []const std.zig.Ast.Node.Index, node: std.zig.Ast.Node.Index) bool {
    for (nodes) |n| if (n == node) return true;
    return false;
}

pub fn collect(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
) std.mem.Allocator.Error!void {
    // Precompute the forbidden field-name nodes ONCE (rare; usually empty) so the
    // per-literal skip check below is O(1) amortized instead of O(n) per literal.
    const field_name_nodes = try containerFieldNameNodes(collector.allocator, parsed.tree);
    const node_tags = parsed.tree.nodes.items(.tag);
    const li = try source_map.LineIndex.init(collector.allocator, parsed.tree.source);
    for (node_tags, 0..) |tag, i| {
        if (tag != .identifier) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        const tok = parsed.tree.nodeMainToken(node);
        const text = parsed.tree.tokenSlice(tok);
        const replacement = replacementFor(text) orelse continue;
        const start = parsed.tree.tokenStart(tok);
        if (ast_backend.inTestBody(test_ranges, start)) continue;
        // A `true`/`false` enum field DECLARATION is a forbidden context: mutating
        // the name would emit a guaranteed `duplicate enum member` compile_error,
        // not a real boolean swap.
        if (nodeInList(field_name_nodes, node)) continue;
        const end = start + @as(u32, @intCast(text.len));
        const start_pos = li.locate(start) orelse continue;
        const end_pos = li.locate(end) orelse continue;
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
