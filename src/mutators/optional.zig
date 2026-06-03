// Layer: deterministic_core
//
// Optional/null AST mutators (docs/MUTATOR_SPEC.md, Phase 2):
//   `optional_orelse_unreachable`: `optional orelse fallback` -> `optional orelse unreachable`
//   `optional_null_check`: swap `x == null` <-> `x != null` (operand-order aware)
// The comparison mutator deliberately leaves null equality comparisons to this
// module. Pure: emits candidates through the shared collector; no patching or
// execution.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator_orelse_unreachable = "optional_orelse_unreachable";
pub const operator_null_check = "optional_null_check";

const orelse_risks = [_][]const u8{
    "tests never pass null",
    "fallback already unreachable through invariants",
};
const null_risks = [_][]const u8{
    "null and non-null paths behave identically in tests",
    "null branch untested",
};

pub fn collect(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
) std.mem.Allocator.Error!void {
    const node_tags = parsed.tree.nodes.items(.tag);
    for (node_tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        switch (tag) {
            .@"orelse" => try collectOrelse(collector, parsed, file, test_ranges, node),
            .equal_equal => try collectNullCheck(collector, parsed, file, test_ranges, node, "!="),
            .bang_equal => try collectNullCheck(collector, parsed, file, test_ranges, node, "=="),
            else => {},
        }
    }
}

/// `optional orelse fallback` -> `optional orelse unreachable`. The candidate
/// span covers the fallback expression (the `orelse` right-hand side). Compile
/// expectation is `may_fail`: the AST layer cannot prove `unreachable` coerces.
fn collectOrelse(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
    node: std.zig.Ast.Node.Index,
) std.mem.Allocator.Error!void {
    const tree = parsed.tree;
    const rhs = tree.nodeData(node).node_and_node[1]; // fallback expression
    const first = tree.firstToken(rhs);
    const last = tree.lastToken(rhs);
    const start = tree.tokenStart(first);
    const last_slice = tree.tokenSlice(last);
    const end = tree.tokenStart(last) + @as(u32, @intCast(last_slice.len));
    if (ast_backend.inTestBody(test_ranges, start)) return;
    const original = tree.source[start..end];
    // An existing `orelse unreachable` (any spelling, e.g. `(unreachable)`) is a
    // forbidden context: re-mutating it would emit a pure-formatting no-op (L6).
    if (mutant.equivalentToCanonical(original, "unreachable")) return;
    const start_pos = source_map.locate(tree.source, start) orelse return;
    const end_pos = source_map.locate(tree.source, end) orelse return;
    try collector.add(.{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = operator_orelse_unreachable,
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
        .equivalent_risks = &orelse_risks,
    });
}

fn isNullToken(parsed: ast_backend.Parsed, tok: u32) bool {
    if (tok >= parsed.tree.tokens.len) return false;
    return std.mem.eql(u8, parsed.tree.tokenSlice(tok), "null");
}

/// Swap an equality comparison against the `null` literal (`x == null`,
/// `x != null`, `null == x`, `null != x`). Operand-order aware. Compile
/// expectation is `compiles`: swapping `==`<->`!=` type-checks identically.
fn collectNullCheck(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
    node: std.zig.Ast.Node.Index,
    replacement: []const u8,
) std.mem.Allocator.Error!void {
    const tree = parsed.tree;
    const op_tok = tree.nodeMainToken(node);
    const op_start = tree.tokenStart(op_tok);
    if (ast_backend.inTestBody(test_ranges, op_start)) return;
    const right_is_null = isNullToken(parsed, op_tok + 1);
    const left_is_null = op_tok > 0 and isNullToken(parsed, op_tok - 1);
    if (!right_is_null and !left_is_null) return;
    const op_text = tree.tokenSlice(op_tok);
    const op_end = op_start + @as(u32, @intCast(op_text.len));
    const start_pos = source_map.locate(tree.source, op_start) orelse return;
    const end_pos = source_map.locate(tree.source, op_end) orelse return;
    try collector.add(.{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = operator_null_check,
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
        .equivalent_risks = &null_risks,
    });
}
