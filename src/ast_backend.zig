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
/// candidate set. Recognizers feed candidates through `add`; this
/// spike only provides the collection/ordering interface and enables no
/// operators itself.
pub const Collector = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Candidate),
    invalid_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Collector {
        return .{ .allocator = allocator, .items = .empty };
    }

    pub fn add(self: *Collector, candidate: Candidate) std.mem.Allocator.Error!void {
        if (!candidate.hasValidEditShape()) {
            self.invalid_count += 1;
            return;
        }
        // Own `original` in the collector's long-lived allocator so it outlives
        // the parsed tree. The stable operators capture `original` as a borrowed
        // slice of `parsed.owned_source` (e.g. `tree.source[start..end]` or
        // `tokenSlice`), but `run_command.generateCandidates` runs
        // `defer parsed.deinit()` per file, freeing that source before
        // `sandbox.apply` reads `original`. Duping here -- while `parsed` is still
        // alive -- captures the correct bytes, so any candidate with a valid
        // patch is executed and classified rather than silently dropped to
        // `invalid` (adversarial audit F-1; I-011). `original` is the only field
        // that borrows the parsed tree: `file` is the caller's long-lived slice,
        // and `replacement`/`operator`/`backend_version`/`equivalent_risks` are
        // static or already allocator-owned.
        var owned = candidate;
        owned.original = try self.allocator.dupe(u8, candidate.original);
        try self.items.append(self.allocator, owned);
    }

    pub fn invalidCount(self: Collector) usize {
        return self.invalid_count;
    }

    /// Assign durable ids, sort by canonical candidate order, and remove
    /// exact-identity duplicates.
    pub fn finish(self: *Collector) std.mem.Allocator.Error![]mutant.Mutant {
        const raw = try self.finishRaw();
        return mutant.sortAndDedupe(self.allocator, raw);
    }

    /// Assign durable ids and return every valid candidate without physical-edit
    /// dedupe. Callers that apply config/operator filters must use this first and
    /// dedupe only the kept set, otherwise a disabled operator can erase the
    /// enabled representative of the same physical edit.
    pub fn finishRaw(self: *Collector) std.mem.Allocator.Error![]mutant.Mutant {
        for (self.items.items) |*candidate| try mutant.assignId(self.allocator, candidate);
        return self.allocator.dupe(mutant.Mutant, self.items.items);
    }

    pub fn deinit(self: *Collector) void {
        self.items.deinit(self.allocator);
    }
};

/// Half-open byte range `[start, end)` of a source region.
pub const ByteRange = struct { start: u32, end: u32 };

/// Byte ranges of every `test` declaration in the parsed source. Mutation
/// excludes candidates inside these ranges by default so it does not target test
/// bodies (docs/INVARIANTS.md I-009).
pub fn testDeclRanges(parsed: Parsed, arena: std.mem.Allocator) std.mem.Allocator.Error![]ByteRange {
    var out: std.ArrayList(ByteRange) = .empty;
    const node_tags = parsed.tree.nodes.items(.tag);
    const token_tags = parsed.tree.tokens.items(.tag);
    for (node_tags, 0..) |tag, i| {
        if (tag != .test_decl) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        const first_tok = parsed.tree.firstToken(node); // the `test` keyword
        const start = parsed.tree.tokenStart(first_tok);
        // Span the whole declaration through its body's matching close brace.
        // Token-scan brace matching is robust and avoids depending on parser
        // node-data layout for body extraction.
        var t: u32 = first_tok;
        while (t < token_tags.len and token_tags[t] != .l_brace) t += 1;
        var depth: u32 = 0;
        var end: u32 = start;
        while (t < token_tags.len) : (t += 1) {
            switch (token_tags[t]) {
                .l_brace => depth += 1,
                .r_brace => {
                    depth -= 1;
                    if (depth == 0) {
                        end = parsed.tree.tokenStart(t) + 1; // `}` is one byte
                        break;
                    }
                },
                else => {},
            }
        }
        try out.append(arena, .{ .start = start, .end = end });
    }
    return out.toOwnedSlice(arena);
}

/// A `test` declaration's name and 1-based line, for same-file test selection
/// (docs/TEST_SELECTION.md). `name` is the test's string-literal or identifier
/// name, or empty for an anonymous `test { ... }`.
pub const TestDecl = struct {
    name: []const u8,
    line: u32,
    byte_start: u32,
};

/// Names and locations of every `test` declaration in the parsed source, in
/// source order. Used by test selection to discover same-file tests.
pub fn testDecls(parsed: Parsed, arena: std.mem.Allocator) std.mem.Allocator.Error![]TestDecl {
    var out: std.ArrayList(TestDecl) = .empty;
    const node_tags = parsed.tree.nodes.items(.tag);
    const token_tags = parsed.tree.tokens.items(.tag);
    const li = try source_map.LineIndex.init(arena, parsed.tree.source);
    for (node_tags, 0..) |tag, i| {
        if (tag != .test_decl) continue;
        const node: std.zig.Ast.Node.Index = @enumFromInt(@as(u32, @intCast(i)));
        const test_tok = parsed.tree.firstToken(node); // the `test` keyword
        const name_tok = test_tok + 1;
        const name: []const u8 = if (name_tok < token_tags.len) switch (token_tags[name_tok]) {
            .string_literal => stripQuotes(parsed.tree.tokenSlice(name_tok)),
            .identifier => parsed.tree.tokenSlice(name_tok),
            else => "", // anonymous `test { ... }`
        } else "";
        const start = parsed.tree.tokenStart(test_tok);
        const pos = li.locate(start) orelse source_map.Position{ .line = 1, .column = 1 };
        try out.append(arena, .{ .name = try arena.dupe(u8, name), .line = pos.line, .byte_start = start });
    }
    return out.toOwnedSlice(arena);
}

fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    return s;
}

/// True if byte offset `at` lies within any test declaration range.
pub fn inTestBody(ranges: []const ByteRange, at: u32) bool {
    for (ranges) |r| {
        if (at >= r.start and at < r.end) return true;
    }
    return false;
}

/// Drop candidates whose site falls inside a `test` declaration, keeping
/// production candidates in the same file. Deterministic and kept separate from
/// test selection.
pub fn excludeTestBodyCandidates(arena: std.mem.Allocator, candidates: []const Candidate, ranges: []const ByteRange) std.mem.Allocator.Error![]Candidate {
    var out: std.ArrayList(Candidate) = .empty;
    for (candidates) |candidate| {
        if (!inTestBody(ranges, @intCast(candidate.span.byte_start))) try out.append(arena, candidate);
    }
    return out.toOwnedSlice(arena);
}
