// Layer: deterministic_core
//
// Error-path AST mutators (docs/MUTATOR_SPEC.md, Phase 2):
//   `error_catch_unreachable`: `expr catch handler` -> `expr catch unreachable`
//   `errdefer_remove`:         `errdefer statement` -> `errdefer {}`
// The catch candidate span is the exact handler expression (the `catch`
// right-hand side); for a `catch |err| handler` form only the handler is
// replaced, never the `|err|` capture. The errdefer candidate span is the whole
// `errdefer <body>` statement, replaced wholesale with `errdefer {}` (an empty,
// no-op error-cleanup). Pure: emits candidates through the shared collector; no
// patching or execution.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const source_map = @import("../source_map.zig");

pub const operator_catch_unreachable = "error_catch_unreachable";
pub const operator_errdefer_remove = "errdefer_remove";

const catch_risks = [_][]const u8{
    "error path never exercised",
    "handler already terminates",
};
const errdefer_risks = [_][]const u8{
    "error path untested",
    "cleanup not observable",
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
            .@"catch" => try collectCatch(collector, parsed, file, test_ranges, node),
            .@"errdefer" => try collectErrdefer(collector, parsed, file, test_ranges, node),
            else => {},
        }
    }
}

/// `expr catch handler` -> `expr catch unreachable`. Replaces only the handler
/// expression; skips an existing `catch unreachable`.
fn collectCatch(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
    node: std.zig.Ast.Node.Index,
) std.mem.Allocator.Error!void {
    const tree = parsed.tree;
    const handler = tree.nodeData(node).node_and_node[1]; // catch right-hand side
    const first = tree.firstToken(handler);
    const last = tree.lastToken(handler);
    const start = tree.tokenStart(first);
    const end = tree.tokenStart(last) + @as(u32, @intCast(tree.tokenSlice(last).len));
    if (ast_backend.inTestBody(test_ranges, start)) return;
    const original = tree.source[start..end];
    if (std.mem.eql(u8, original, "unreachable")) return; // existing catch unreachable
    const start_pos = source_map.locate(tree.source, start) orelse return;
    const end_pos = source_map.locate(tree.source, end) orelse return;
    try collector.add(.{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = operator_catch_unreachable,
        .operator_stability = .stable,
        .file = file,
        .span = .{ .byte_start = start, .byte_end = end, .line_start = start_pos.line, .column_start = start_pos.column, .line_end = end_pos.line, .column_end = end_pos.column },
        .original = original,
        .replacement = "unreachable",
        .expected_compile = .may_fail,
        .equivalent_risks = &catch_risks,
    });
}

/// `errdefer <body>` -> `errdefer {}`. Spans the whole errdefer statement (the
/// `errdefer` keyword through the cleanup body) and replaces it with an empty
/// no-op errdefer; skips an existing `errdefer {}`. Compile expectation is
/// `may_fail`: removing the only use of a captured resource can make it unused.
fn collectErrdefer(
    collector: *ast_backend.Collector,
    parsed: ast_backend.Parsed,
    file: []const u8,
    test_ranges: []const ast_backend.ByteRange,
    node: std.zig.Ast.Node.Index,
) std.mem.Allocator.Error!void {
    const tree = parsed.tree;
    const kw = tree.nodeMainToken(node); // the `errdefer` keyword
    const last = tree.lastToken(node); // end of the cleanup body
    const start = tree.tokenStart(kw);
    const end = tree.tokenStart(last) + @as(u32, @intCast(tree.tokenSlice(last).len));
    if (ast_backend.inTestBody(test_ranges, start)) return;
    const original = tree.source[start..end];
    const replacement = "errdefer {}";
    if (std.mem.eql(u8, original, replacement)) return; // already an empty errdefer
    const start_pos = source_map.locate(tree.source, start) orelse return;
    const end_pos = source_map.locate(tree.source, end) orelse return;
    try collector.add(.{
        .id = "",
        .backend = .ast,
        .backend_version = mutant.ast_backend_version,
        .backend_stability = .stable,
        .operator = operator_errdefer_remove,
        .operator_stability = .stable,
        .file = file,
        .span = .{ .byte_start = start, .byte_end = end, .line_start = start_pos.line, .column_start = start_pos.column, .line_end = end_pos.line, .column_end = end_pos.column },
        .original = original,
        .replacement = replacement,
        .expected_compile = .may_fail,
        .equivalent_risks = &errdefer_risks,
    });
}
