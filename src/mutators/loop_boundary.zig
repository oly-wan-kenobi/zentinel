// Layer: deterministic_core
//
// Loop boundary AST mutator (docs/MUTATOR_SPEC.md, Phase 2):
//   `loop_boundary`: swap the inclusive/exclusive boundary of a `while` loop's
//   comparison condition (`<`<->`<=`, `>`<->`>=`), and increment/decrement the
//   end of a `for` range (`a..b` -> `a..b+1` / `a..b-1`) when the end is a plain
//   integer literal. Infinite loops (`while (true)`), non-comparison conditions,
//   non-integer or open range ends, and test bodies are skipped. Pure: emits
//   candidates through the shared collector; no patching or execution.
//
// Relationship with `comparison_boundary`: a `while` condition's boundary swap is
// the SAME physical edit `comparison_boundary` emits for that comparison node
// (identical file/span/original/replacement). When BOTH operators are enabled,
// `sortAndDedupe` (mutant.samePhysicalEdit) keeps exactly one representative -- the
// alphabetically-first operator, `comparison_boundary` -- so the while-condition
// candidate emitted here is intentionally deduped away (no duplicate mutant). This
// branch is therefore only the producing operator for while conditions when
// `comparison_boundary` is disabled; `loop_boundary`'s unique contribution when
// both are on is the `for`-range increment/decrement, which no other operator
// emits. This redundancy is intended, not a missed mutation.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator = "loop_boundary";

const risks = [_][]const u8{
    "empty loops",
    "tests only cover zero iterations",
    "sentinel values",
};

fn boundarySwap(tag: std.zig.Ast.Node.Tag) ?[]const u8 {
    return switch (tag) {
        .less_than => "<=",
        .less_or_equal => "<",
        .greater_than => ">=",
        .greater_or_equal => ">",
        else => null,
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
    const li = try source_map.LineIndex.init(collector.allocator, tree.source);
    for (node_tags, 0..) |tag, i| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        switch (tag) {
            .while_simple => try whileCond(collector, parsed, file, test_ranges, node_tags, tree.nodeData(node).node_and_node[0], li),
            .while_cont, .@"while" => try whileCond(collector, parsed, file, test_ranges, node_tags, tree.nodeData(node).node_and_extra[0], li),
            .for_range => try rangeEnd(collector, parsed, file, test_ranges, node_tags, node, li),
            else => {},
        }
    }
}

/// Swap the boundary of a `while` condition comparison. The swap always
/// type-checks, so the compile expectation is `compiles`.
fn whileCond(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
    node_tags: []const std.zig.Ast.Node.Tag,
    cond: std.zig.Ast.Node.Index,
    li: source_map.LineIndex,
) std.mem.Allocator.Error!void {
    const ci = @intFromEnum(cond);
    if (ci >= node_tags.len) return;
    const swap = boundarySwap(node_tags[ci]) orelse return;
    const tree = parsed.tree;
    const op_tok = tree.nodeMainToken(cond);
    const start = tree.tokenStart(op_tok);
    if (ast_backend.inTestBody(test_ranges, start)) return;
    const text = tree.tokenSlice(op_tok);
    const end = start + @as(u32, @intCast(text.len));
    const sp = li.locate(start) orelse return;
    const ep = li.locate(end) orelse return;
    try collector.add(.{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = operator,
        .operator_stability = .stable,
        .file = file,
        .span = .{ .byte_start = start, .byte_end = end, .line_start = sp.line, .column_start = sp.column, .line_end = ep.line, .column_end = ep.column },
        .original = text,
        .replacement = swap,
        .expected_compile = .compiles,
        .equivalent_risks = &risks,
    });
}

/// Increment/decrement the end of a `for` range when it is a plain integer
/// literal. Compile expectation is `may_fail` (the +/-1 can overflow the range
/// type or form an invalid range).
fn rangeEnd(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
    node_tags: []const std.zig.Ast.Node.Tag,
    node: std.zig.Ast.Node.Index,
    li: source_map.LineIndex,
) std.mem.Allocator.Error!void {
    const tree = parsed.tree;
    const end_node = (tree.nodeData(node).node_and_opt_node[1]).unwrap() orelse return; // open range `a..`
    const ei = @intFromEnum(end_node);
    if (ei >= node_tags.len or node_tags[ei] != .number_literal) return;
    const tok = tree.nodeMainToken(end_node);
    const start = tree.tokenStart(tok);
    if (ast_backend.inTestBody(test_ranges, start)) return;
    const text = tree.tokenSlice(tok);
    if (!isPlainDecimal(text)) return;
    const value = std.fmt.parseInt(i128, text, 10) catch return;
    const end = start + @as(u32, @intCast(text.len));
    const sp = li.locate(start) orelse return;
    const ep = li.locate(end) orelse return;
    const span: mutant.Span = .{ .byte_start = start, .byte_end = end, .line_start = sp.line, .column_start = sp.column, .line_end = ep.line, .column_end = ep.column };
    // Guard the range-end arithmetic against i128 overflow exactly as
    // integer_boundary does: a +/-1 boundary unrepresentable in i128 is skipped
    // rather than computed, since the unchecked add/sub would panic in-process and
    // abort the whole candidate-generation pass on a legal source literal.
    if (std.math.add(i128, value, 1)) |plus| {
        try emitRange(collector, file, span, text, try std.fmt.allocPrint(collector.allocator, "{d}", .{plus}));
    } else |_| {}
    if (std.math.sub(i128, value, 1)) |minus| {
        try emitRange(collector, file, span, text, try std.fmt.allocPrint(collector.allocator, "{d}", .{minus}));
    } else |_| {}
}

fn emitRange(
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
