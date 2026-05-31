// Layer: deterministic_core
//
// Deterministic doctest case extraction (docs/DOCTEST_ARCHITECTURE.md "Case
// Planning"). It groups parsed blocks into typed cases, assigns durable
// `dt_...` ids, and reports ambiguous/invalid groupings as
// ZNTL_DOCTEST_INVALID_BLOCK diagnostics. It executes nothing: no commands and
// no compiler invocations. Output is sorted and serializable for later reports.
const std = @import("std");
const block = @import("block.zig");
const case = @import("case.zig");
const parser = @import("parser.zig");
const error_codes = @import("../error_codes.zig");

pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    line: u32,
};

pub const Extracted = struct {
    cases: []const case.Case,
    diagnostics: []const Diagnostic,
};

/// The producer case kind a block can anchor, or null if the block is an
/// expectation/secondary block (or an unsupported standalone block).
fn producerKind(b: block.Block) ?case.CaseKind {
    return switch (b.kind) {
        .unit_test => .zig_test,
        .compile_fail => .zig_compile_fail,
        .cli => .cli,
        .config => .config,
        .config_fail => .config_fail,
        .before => .mutation,
        .none => if (b.language == .zig) .zig_compile_pass else null,
        else => null,
    };
}

fn isExpectation(b: block.Block) bool {
    return b.kind == .expected or b.kind == .output;
}

const GroupBuilder = struct {
    kind: case.CaseKind,
    anchor_idx: usize,
    indices: std.ArrayList(usize),
    needs_after: bool,
    invalid: bool,
};

/// Parse `source` then extract cases. Parser diagnostics are merged in.
pub fn extractSource(arena: std.mem.Allocator, file: []const u8, source: []const u8) std.mem.Allocator.Error!Extracted {
    const parsed = try parser.parse(arena, file, source);
    return extract(arena, file, parsed.blocks, parsed.diagnostics);
}

/// Group an already-parsed block list into typed cases. `parse_diags` are
/// folded into the result so callers see parser and extraction problems
/// together.
pub fn extract(
    arena: std.mem.Allocator,
    file: []const u8,
    blocks: []const block.Block,
    parse_diags: []const parser.Diagnostic,
) std.mem.Allocator.Error!Extracted {
    var diags: std.ArrayList(Diagnostic) = .empty;
    for (parse_diags) |d| {
        try diags.append(arena, .{ .code = d.code, .message = d.message, .line = d.line });
    }

    var groups: std.ArrayList(GroupBuilder) = .empty;
    var current: ?usize = null;

    for (blocks, 0..) |b, idx| {
        if (!b.is_doctest) {
            // A documentation-only block ends implicit grouping.
            current = null;
            continue;
        }
        if (producerKind(b)) |k| {
            var indices: std.ArrayList(usize) = .empty;
            try indices.append(arena, idx);
            try groups.append(arena, .{
                .kind = k,
                .anchor_idx = idx,
                .indices = indices,
                .needs_after = (b.kind == .before),
                .invalid = false,
            });
            current = groups.items.len - 1;
        } else if (isExpectation(b)) {
            if (current) |ci| {
                const g = &groups.items[ci];
                if (g.kind == .zig_compile_pass) {
                    // Plain compile-pass snippets have no stable output contract.
                    try diags.append(arena, .{
                        .code = error_codes.doctest_invalid_block,
                        .message = "compile-pass block cannot take an expected-output block",
                        .line = b.line_start,
                    });
                    g.invalid = true;
                    current = null;
                } else {
                    try g.indices.append(arena, idx);
                }
            } else {
                try diags.append(arena, .{
                    .code = error_codes.doctest_invalid_block,
                    .message = "expectation block has no preceding producer",
                    .line = b.line_start,
                });
            }
        } else if (b.kind == .after) {
            if (current != null and groups.items[current.?].needs_after) {
                const g = &groups.items[current.?];
                try g.indices.append(arena, idx);
                g.needs_after = false;
            } else {
                try diags.append(arena, .{
                    .code = error_codes.doctest_invalid_block,
                    .message = "zig after without a preceding zig before",
                    .line = b.line_start,
                });
            }
        } else {
            // Any other recognized doctest block ends implicit grouping.
            current = null;
        }
    }

    // Finalize groups into candidate cases.
    var candidates: std.ArrayList(case.Case) = .empty;
    for (groups.items) |g| {
        if (g.invalid) continue;
        const anchor = blocks[g.anchor_idx];
        if (g.needs_after) {
            try diags.append(arena, .{
                .code = error_codes.doctest_invalid_block,
                .message = "zig before without a matching zig after",
                .line = anchor.line_start,
            });
            continue;
        }

        const grouping = try groupingMetadata(arena, blocks, g.indices.items);
        const content_hash = try contentHashHex(arena, blocks, g.indices.items);
        const id_arr = case.computeId(.{
            .file = file,
            .kind = g.kind,
            .label = anchor.case_label orelse "",
            .grouping = grouping,
            .content_hash = content_hash,
        });

        var refs: std.ArrayList([]const u8) = .empty;
        for (g.indices.items) |bi| {
            try refs.append(arena, try formatRef(arena, file, blocks[bi].line_start, blocks[bi].case_label));
        }
        const last = blocks[g.indices.items[g.indices.items.len - 1]];

        try candidates.append(arena, .{
            .id = try arena.dupe(u8, &id_arr),
            .file = file,
            .kind = g.kind,
            .label = anchor.case_label,
            .source_ref = try formatRef(arena, file, anchor.line_start, anchor.case_label),
            .block_refs = try refs.toOwnedSlice(arena),
            .line_start = anchor.line_start,
            .line_end = last.line_end,
            .anchor_line = anchor.line_start,
        });
    }

    // Duplicate unlabeled identical cases share a durable id; reject all of
    // them as ambiguous instead of minting occurrence-based ids.
    var cases: std.ArrayList(case.Case) = .empty;
    for (candidates.items, 0..) |c, i| {
        var duplicate = false;
        for (candidates.items, 0..) |c2, j| {
            if (i != j and std.mem.eql(u8, c.id, c2.id)) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) {
            try diags.append(arena, .{
                .code = error_codes.doctest_invalid_block,
                .message = "duplicate unlabeled identical doctest cases; add explicit case labels",
                .line = c.anchor_line,
            });
        } else {
            try cases.append(arena, c);
        }
    }

    const case_slice = try cases.toOwnedSlice(arena);
    std.mem.sort(case.Case, case_slice, {}, caseLessThan);
    const diag_slice = try diags.toOwnedSlice(arena);
    std.mem.sort(Diagnostic, diag_slice, {}, diagLessThan);

    return .{ .cases = case_slice, .diagnostics = diag_slice };
}

fn groupingMetadata(arena: std.mem.Allocator, blocks: []const block.Block, indices: []const usize) std.mem.Allocator.Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (indices, 0..) |bi, n| {
        if (n != 0) try buf.append(arena, ';');
        try buf.appendSlice(arena, @tagName(blocks[bi].kind));
        try buf.append(arena, ':');
        try buf.appendSlice(arena, @tagName(blocks[bi].match_mode));
    }
    return buf.toOwnedSlice(arena);
}

fn contentHashHex(arena: std.mem.Allocator, blocks: []const block.Block, indices: []const usize) std.mem.Allocator.Error![]const u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    for (indices) |bi| {
        h.update(@tagName(blocks[bi].kind));
        h.update("\x00");
        h.update(blocks[bi].content);
        h.update("\x00");
    }
    var digest: [32]u8 = undefined;
    h.final(&digest);
    return hexLower(arena, &digest);
}

fn hexLower(arena: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    const hex = "0123456789abcdef";
    const out = try arena.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, i| {
        out[i * 2] = hex[byte >> 4];
        out[i * 2 + 1] = hex[byte & 0x0f];
    }
    return out;
}

fn formatRef(arena: std.mem.Allocator, file: []const u8, line: u32, label: ?[]const u8) std.mem.Allocator.Error![]const u8 {
    if (label) |l| return std.fmt.allocPrint(arena, "{s}:{d}:{s}", .{ file, line, l });
    return std.fmt.allocPrint(arena, "{s}:{d}", .{ file, line });
}

fn caseLessThan(_: void, a: case.Case, b: case.Case) bool {
    const f = std.mem.order(u8, a.file, b.file);
    if (f != .eq) return f == .lt;
    if (a.anchor_line != b.anchor_line) return a.anchor_line < b.anchor_line;
    if (a.line_start != b.line_start) return a.line_start < b.line_start;
    return std.mem.order(u8, a.id, b.id) == .lt;
}

fn diagLessThan(_: void, a: Diagnostic, b: Diagnostic) bool {
    if (a.line != b.line) return a.line < b.line;
    const c = std.mem.order(u8, a.code, b.code);
    if (c != .eq) return c == .lt;
    return std.mem.order(u8, a.message, b.message) == .lt;
}

/// Render a deterministic JSON inventory of the extraction. Durable `id`, the
/// anchor `source_ref`, secondary `block_refs`, and display-only location
/// fields are kept as separate fields. Serializable for future reports.
pub fn renderInventory(arena: std.mem.Allocator, ex: Extracted) std.mem.Allocator.Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(arena, "{\n  \"cases\": [");
    for (ex.cases, 0..) |c, i| {
        try buf.appendSlice(arena, if (i == 0) "\n" else ",\n");
        try buf.appendSlice(arena, "    {\n");
        try jsonField(arena, &buf, "id", c.id, true);
        try jsonField(arena, &buf, "file", c.file, true);
        try jsonField(arena, &buf, "kind", c.kind.toString(), true);
        try buf.appendSlice(arena, "      \"label\": ");
        if (c.label) |l| {
            try jsonString(arena, &buf, l);
        } else {
            try buf.appendSlice(arena, "null");
        }
        try buf.appendSlice(arena, ",\n");
        try jsonField(arena, &buf, "source_ref", c.source_ref, true);
        try buf.appendSlice(arena, "      \"block_refs\": [");
        for (c.block_refs, 0..) |r, j| {
            if (j != 0) try buf.appendSlice(arena, ", ");
            try jsonString(arena, &buf, r);
        }
        try buf.appendSlice(arena, "],\n");
        try jsonNumberField(arena, &buf, "line_start", c.line_start);
        try jsonNumberField(arena, &buf, "line_end", c.line_end);
        try jsonNumberFieldLast(arena, &buf, "anchor_line", c.anchor_line);
        try buf.appendSlice(arena, "    }");
    }
    try buf.appendSlice(arena, if (ex.cases.len == 0) "],\n" else "\n  ],\n");

    try buf.appendSlice(arena, "  \"diagnostics\": [");
    for (ex.diagnostics, 0..) |d, i| {
        try buf.appendSlice(arena, if (i == 0) "\n" else ",\n");
        try buf.appendSlice(arena, "    {\n");
        try jsonField(arena, &buf, "code", d.code, true);
        try jsonNumberField(arena, &buf, "line", d.line);
        try buf.appendSlice(arena, "      \"message\": ");
        try jsonString(arena, &buf, d.message);
        try buf.appendSlice(arena, "\n    }");
    }
    try buf.appendSlice(arena, if (ex.diagnostics.len == 0) "]\n}\n" else "\n  ]\n}\n");

    return buf.toOwnedSlice(arena);
}

fn jsonField(arena: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, value: []const u8, comptime trailing: bool) std.mem.Allocator.Error!void {
    try buf.appendSlice(arena, "      \"");
    try buf.appendSlice(arena, name);
    try buf.appendSlice(arena, "\": ");
    try jsonString(arena, buf, value);
    try buf.appendSlice(arena, if (trailing) ",\n" else "\n");
}

fn jsonNumberField(arena: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, value: u32) std.mem.Allocator.Error!void {
    try buf.appendSlice(arena, "      \"");
    try buf.appendSlice(arena, name);
    try buf.appendSlice(arena, "\": ");
    try buf.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{value}));
    try buf.appendSlice(arena, ",\n");
}

fn jsonNumberFieldLast(arena: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, value: u32) std.mem.Allocator.Error!void {
    try buf.appendSlice(arena, "      \"");
    try buf.appendSlice(arena, name);
    try buf.appendSlice(arena, "\": ");
    try buf.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{value}));
    try buf.appendSlice(arena, "\n");
}

fn jsonString(arena: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) std.mem.Allocator.Error!void {
    try buf.append(arena, '"');
    for (s) |ch| {
        switch (ch) {
            '"' => try buf.appendSlice(arena, "\\\""),
            '\\' => try buf.appendSlice(arena, "\\\\"),
            '\n' => try buf.appendSlice(arena, "\\n"),
            '\t' => try buf.appendSlice(arena, "\\t"),
            '\r' => try buf.appendSlice(arena, "\\r"),
            else => try buf.append(arena, ch),
        }
    }
    try buf.append(arena, '"');
}
