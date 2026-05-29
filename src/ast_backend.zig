// Layer: deterministic_core
//
// AST parsing adapter for Phase 1 candidate discovery (docs/AST_BACKEND.md).
// Wraps the pinned `std.zig.Ast` parser for Zig 0.16.0 behind zentinel's own
// interface so a future Zig pin change is isolated to this module. This spike
// only parses, maps locations, reports diagnostics, and exposes deterministic
// traversal; it does not generate mutants.
//
// Verified `std.zig.Ast` API surface (Zig 0.16.0):
//   - std.zig.Ast.parse(gpa, source: [:0]const u8, mode: .zig) Allocator.Error!Ast
//   - Ast.deinit(gpa); Ast.source: [:0]const u8; Ast.errors: []const Ast.Error
//   - Ast.errorOffset(Error) u32; Ast.Error.tag (@tagName for a stable label)
//   - Ast.nodes: MultiArrayList(Node).Slice; nodes.items(.tag) -> []Node.Tag
const std = @import("std");
const source_map = @import("source_map.zig");
const mutant = @import("mutant.zig");

/// A parse diagnostic mapped to a file and 1-based location. `message` is the
/// stable `std.zig.Ast` error tag name; full human rendering is deferred.
pub const Diagnostic = struct {
    file: []const u8,
    byte_offset: u32,
    line: u32,
    column: u32,
    message: []const u8,
};

/// Owns the parsed tree, the null-terminated source it references, and any
/// diagnostics. Call `deinit` to release everything.
pub const Parsed = struct {
    tree: std.zig.Ast,
    owned_source: [:0]u8,
    file: []u8,
    diags: []Diagnostic,
    gpa: std.mem.Allocator,

    pub fn ok(self: Parsed) bool {
        return self.diags.len == 0;
    }

    pub fn diagnostics(self: Parsed) []const Diagnostic {
        return self.diags;
    }

    pub fn nodeCount(self: Parsed) usize {
        return self.tree.nodes.len;
    }

    /// Deterministic traversal signature: node tag names in node-index order,
    /// comma-separated. Identical for identical source, independent of any map
    /// or filesystem iteration.
    pub fn traversalSignature(self: Parsed, arena: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        const tags = self.tree.nodes.items(.tag);
        for (tags, 0..) |tag, i| {
            if (i > 0) try out.append(arena, ',');
            try out.appendSlice(arena, @tagName(tag));
        }
        return out.toOwnedSlice(arena);
    }

    pub fn deinit(self: *Parsed) void {
        self.tree.deinit(self.gpa);
        self.gpa.free(self.owned_source);
        self.gpa.free(self.file);
        self.gpa.free(self.diags);
        self.* = undefined;
    }
};

/// Parse Zig `source` for project-relative `file`. The adapter owns a
/// null-terminated copy of the source that the returned tree references.
pub fn parse(gpa: std.mem.Allocator, file: []const u8, source: []const u8) !Parsed {
    const owned_source = try gpa.dupeZ(u8, source);
    errdefer gpa.free(owned_source);
    const file_owned = try gpa.dupe(u8, file);
    errdefer gpa.free(file_owned);

    var tree = try std.zig.Ast.parse(gpa, owned_source, .zig);
    errdefer tree.deinit(gpa);

    var diags: std.ArrayList(Diagnostic) = .empty;
    errdefer diags.deinit(gpa);
    for (tree.errors) |parse_error| {
        if (parse_error.is_note) continue; // primary errors carry the location
        const offset = tree.errorOffset(parse_error);
        const pos = source_map.locate(owned_source, offset) orelse source_map.Position{ .line = 1, .column = 1 };
        try diags.append(gpa, .{
            .file = file_owned,
            .byte_offset = offset,
            .line = pos.line,
            .column = pos.column,
            .message = @tagName(parse_error.tag),
        });
    }
    const diags_owned = try diags.toOwnedSlice(gpa);

    return .{
        .tree = tree,
        .owned_source = owned_source,
        .file = file_owned,
        .diags = diags_owned,
        .gpa = gpa,
    };
}

/// A candidate is a shared mutant whose durable id is assigned during collection.
pub const Candidate = mutant.Mutant;

/// Collects AST backend candidates and produces a deterministic, deduplicated
/// candidate set. Recognizers (task 010+) feed candidates through `add`; this
/// spike only provides the collection/ordering interface and enables no
/// operators itself.
pub const Collector = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Candidate),

    pub fn init(allocator: std.mem.Allocator) Collector {
        return .{ .allocator = allocator, .items = .empty };
    }

    pub fn add(self: *Collector, candidate: Candidate) std.mem.Allocator.Error!void {
        try self.items.append(self.allocator, candidate);
    }

    /// Assign durable ids, sort by canonical candidate order, and remove
    /// exact-identity duplicates.
    pub fn finish(self: *Collector) std.mem.Allocator.Error![]mutant.Mutant {
        for (self.items.items) |*candidate| try mutant.assignId(self.allocator, candidate);
        return mutant.sortAndDedupe(self.allocator, self.items.items);
    }

    pub fn deinit(self: *Collector) void {
        self.items.deinit(self.allocator);
    }
};
