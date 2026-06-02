// Layer: deterministic_core
//
// Experimental ZIR backend prototype (docs/ZIR_BACKEND.md). The ZIR backend is
// disabled by default and reachable only through explicit config or CLI opt-in.
// This prototype is a deterministic adapter: it derives ZIR candidates from the
// stable AST candidate set so source mapping is exact by construction, re-tagging
// supported condition operators with `backend = .zir` and
// `backend_stability = .experimental`. Operators whose source mapping needs
// type-level ZIR context the prototype cannot map exactly (arithmetic and literal
// rewrites) are NOT emitted as mutants; they become out-of-report backend
// diagnostics so they never affect mutation score, survivor counts, or report v1
// fields. Live compiler-internal ZIR introspection is intentionally out of scope
// here: report v1 stays closed. At CLI runtime the unsupported evidence is
// surfaced as stderr `note[...]` lines (src/cli.zig); the schema-versioned
// on-disk artifact (`diagnosticsToJson` -> zentinel.experimental_backend_diagnostics.v1,
// intended under artifacts/pipeline/<task-id>/experimental-backend-diagnostics/)
// is defined and tested but its pipeline write is not yet implemented (L25).
// Targets pinned Zig 0.16.0; version coupling is handled by opt-in diagnostics.
const std = @import("std");
const mutant = @import("mutant.zig");
const config = @import("config.zig");
const ast_backend = @import("ast_backend.zig");
const source_map = @import("source_map.zig");

/// Internal deterministic backend contract string for the experimental ZIR
/// prototype under Zig 0.16.0. It participates in durable identity (so a ZIR
/// candidate never collides with the AST candidate at the same span) and is
/// distinct from `mutant.ast_backend_version`.
pub const backend_version = "zir.v1.zig-0.16.0";

/// Out-of-report backend diagnostic for a candidate the ZIR prototype cannot map
/// to an exact source span. It is never a report v1 field.
pub const Diagnostic = struct {
    code: []const u8 = "ZNTL_ZIR_UNSUPPORTED",
    file: []const u8,
    operator: []const u8,
    span_start: u64,
    span_end: u64,
    reason: []const u8,
};

pub const Result = struct {
    candidates: []const mutant.Mutant,
    diagnostics: []const Diagnostic,
};

/// Operators whose source mapping is exact at the ZIR prototype level: boolean,
/// comparison, and logical condition operators map 1:1 to a ZIR condition with
/// the same source span. Arithmetic and integer/loop literal rewrites need
/// type-level ZIR context the prototype cannot map exactly, so they are recorded
/// as diagnostics rather than executed.
const supported_operators = [_][]const u8{
    "comparison_boundary",
    "equality_swap",
    "logical_and_or",
    "boolean_literal",
};

pub fn isSupported(operator: []const u8) bool {
    for (supported_operators) |op| {
        if (std.mem.eql(u8, op, operator)) return true;
    }
    return false;
}

fn reTag(arena: std.mem.Allocator, ast: mutant.Mutant) std.mem.Allocator.Error!mutant.Mutant {
    var c = ast;
    c.backend = .zir;
    c.backend_version = backend_version;
    c.backend_stability = .experimental;
    const id = mutant.computeId(c.identity());
    c.id = try arena.dupe(u8, &id);
    return c;
}

/// Build the experimental ZIR candidate set from the deterministic AST candidate
/// set. Supported operators are re-tagged with exact source mapping inherited
/// from the AST span; unsupported operators become out-of-report diagnostics and
/// are never executable mutants.
pub fn fromAst(arena: std.mem.Allocator, ast_candidates: []const mutant.Mutant) std.mem.Allocator.Error!Result {
    var candidates: std.ArrayList(mutant.Mutant) = .empty;
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    for (ast_candidates) |c| {
        if (isSupported(c.operator)) {
            try candidates.append(arena, try reTag(arena, c));
        } else {
            try diagnostics.append(arena, .{
                .file = c.file,
                .operator = c.operator,
                .span_start = c.span.byte_start,
                .span_end = c.span.byte_end,
                .reason = "operator has no exact ZIR source mapping in the prototype; needs type-level ZIR context",
            });
        }
    }
    return .{
        .candidates = try candidates.toOwnedSlice(arena),
        .diagnostics = try diagnostics.toOwnedSlice(arena),
    };
}

// --- Real ZIR lowering (task 056, Phase 1: comparison operators) ------------
//
// Unlike `fromAst` (the relabel adapter), `fromTree` actually lowers the source
// to ZIR via `std.zig.AstGen` and recognizes comparison mutation sites from the
// `cmp_*` instructions, mapping each back to its exact AST comparison node. The
// candidate metadata mirrors the AST comparison recognizer (src/mutators/comparison.zig,
// which this task may not modify) so the two backends stay in differential parity
// -- the zir_backend parity test pins this. ZIR's real contribution is the lowering
// plus dropping AstGen-injected comparisons (for-bounds, switch ranges) that have
// no source operator. Source mapping: `pl_node.src_node` is an offset from the
// enclosing declaration node, so the comparison node `n` is the one whose
// `n - off` is itself a decl base (innermost wins); injected cmps resolve to none.

pub const FromTreeError = error{BackendParseError} || std.mem.Allocator.Error;

const CmpOp = enum { eq, neq, lt, lte, gt, gte };

fn astCmpOp(t: std.zig.Ast.Node.Tag) ?CmpOp {
    return switch (t) {
        .equal_equal => .eq,
        .bang_equal => .neq,
        .less_than => .lt,
        .less_or_equal => .lte,
        .greater_than => .gt,
        .greater_or_equal => .gte,
        else => null,
    };
}

fn zirCmpOp(t: std.zig.Zir.Inst.Tag) ?CmpOp {
    return switch (t) {
        .cmp_eq => .eq,
        .cmp_neq => .neq,
        .cmp_lt => .lt,
        .cmp_lte => .lte,
        .cmp_gt => .gt,
        .cmp_gte => .gte,
        else => null,
    };
}

/// AST node tags AstGen uses as a declaration base (`decl_node_index`), which a
/// `pl_node.src_node` offset is measured from.
fn isDeclBase(t: std.zig.Ast.Node.Tag) bool {
    return switch (t) {
        .root,
        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        .fn_decl,
        .container_decl,
        .container_decl_trailing,
        .container_decl_two,
        .container_decl_two_trailing,
        .container_decl_arg,
        .container_decl_arg_trailing,
        .tagged_union,
        .tagged_union_trailing,
        .tagged_union_two,
        .tagged_union_two_trailing,
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        .test_decl,
        .simple_var_decl,
        .aligned_var_decl,
        .local_var_decl,
        .global_var_decl,
        => true,
        else => false,
    };
}

/// Resolve a `cmp_*` instruction to its AST comparison node, or null if it is an
/// AstGen-injected comparison with no source operator. The real node `n` (matching
/// `op`) is the one whose `n - off` is a declaration base; the innermost decl
/// (largest such base) wins.
fn resolveCmpNode(tree: std.zig.Ast, is_base: []const bool, op: CmpOp, off: i32, node_count: i64) ?u32 {
    const node_tags = tree.nodes.items(.tag);
    var best: ?u32 = null;
    var best_base: i64 = -1;
    var i: u32 = 0;
    while (i < node_count) : (i += 1) {
        if (astCmpOp(node_tags[i]) != op) continue;
        const base: i64 = @as(i64, i) - off;
        if (base < 0 or base >= node_count) continue;
        if (!is_base[@intCast(base)]) continue;
        if (base > best_base) {
            best = i;
            best_base = base;
        }
    }
    return best;
}

// Comparison swap metadata, mirrored from src/mutators/comparison.zig (a file this
// task may not modify). The parity test guarantees these stay equivalent to the AST
// recognizer; a drift surfaces as a parity failure, not a silent divergence.
const equality_risks = [_][]const u8{
    "values known to differ in all tests",
    "dead branches",
    "comparisons guarded by identical previous checks",
};
const boundary_risks = [_][]const u8{
    "missing exact-boundary inputs",
    "floating-point NaN behavior",
    "values constrained away from boundary",
};
const Swap = struct { operator: []const u8, replacement: []const u8, risks: []const []const u8 };

fn swapFor(tag: std.zig.Ast.Node.Tag) ?Swap {
    return switch (tag) {
        .equal_equal => .{ .operator = "equality_swap", .replacement = "!=", .risks = &equality_risks },
        .bang_equal => .{ .operator = "equality_swap", .replacement = "==", .risks = &equality_risks },
        .less_than => .{ .operator = "comparison_boundary", .replacement = "<=", .risks = &boundary_risks },
        .less_or_equal => .{ .operator = "comparison_boundary", .replacement = "<", .risks = &boundary_risks },
        .greater_than => .{ .operator = "comparison_boundary", .replacement = ">=", .risks = &boundary_risks },
        .greater_or_equal => .{ .operator = "comparison_boundary", .replacement = ">", .risks = &boundary_risks },
        else => null,
    };
}

fn isNullToken(tree: std.zig.Ast, tok: u32) bool {
    if (tok >= tree.tokens.len) return false;
    return std.mem.eql(u8, tree.tokenSlice(tok), "null");
}

/// Lower `source` to ZIR and emit the experimental ZIR comparison candidate set
/// (`equality_swap`, `comparison_boundary`). Candidates are byte-for-byte the AST
/// recognizer's, re-tagged `backend = .zir`; AstGen-injected comparisons become
/// out-of-report diagnostics. Phase 1 covers comparison operators only.
pub fn fromTree(arena: std.mem.Allocator, file: []const u8, source: []const u8) FromTreeError!Result {
    const parsed = ast_backend.parse(arena, file, source) catch return error.BackendParseError;
    if (!parsed.ok()) return error.BackendParseError;
    const tree = parsed.tree;
    const test_ranges = try ast_backend.testDeclRanges(parsed, arena);
    const node_tags = tree.nodes.items(.tag);

    const is_base = try arena.alloc(bool, tree.nodes.len);
    for (node_tags, 0..) |t, i| is_base[i] = isDeclBase(t);
    if (is_base.len > 0) is_base[0] = true; // root is always a base

    var code = try std.zig.AstGen.generate(arena, tree);
    const inst_tags = code.instructions.items(.tag);
    const inst_datas = code.instructions.items(.data);
    const node_count: i64 = @intCast(tree.nodes.len);

    var collector = ast_backend.Collector.init(arena);
    var diagnostics: std.ArrayList(Diagnostic) = .empty;

    for (inst_tags, 0..) |t, i| {
        const cop = zirCmpOp(t) orelse continue;
        const off = @intFromEnum(inst_datas[i].pl_node.src_node);
        const n = resolveCmpNode(tree, is_base, cop, off, node_count) orelse {
            // AstGen-injected comparison (for-bounds / switch range): no source
            // operator, so it is an out-of-report diagnostic, never a mutant.
            try diagnostics.append(arena, .{
                .file = file,
                .operator = "comparison_injected",
                .span_start = 0,
                .span_end = 0,
                .reason = "ZIR comparison with no source operator (compiler-injected bounds/range check)",
            });
            continue;
        };
        const node: std.zig.Ast.Node.Index = @enumFromInt(n);
        const swap = swapFor(node_tags[n]) orelse continue; // resolveCmpNode guarantees a comparison tag
        const op_tok = tree.nodeMainToken(node);
        const op_start = tree.tokenStart(op_tok);
        // Parity with comparison.zig: skip comparisons inside test bodies, and leave
        // `x == null` / `null == x` to optional_null_check.
        if (ast_backend.inTestBody(test_ranges, op_start)) continue;
        if (std.mem.eql(u8, swap.operator, "equality_swap")) {
            const right_null = isNullToken(tree, op_tok + 1);
            const left_null = op_tok > 0 and isNullToken(tree, op_tok - 1);
            if (right_null or left_null) continue;
        }
        const op_text = tree.tokenSlice(op_tok);
        const op_end = op_start + @as(u32, @intCast(op_text.len));
        const start_pos = source_map.locate(tree.source, op_start) orelse continue;
        const end_pos = source_map.locate(tree.source, op_end) orelse continue;
        try collector.add(.{
            .id = "",
            .backend = .zir,
            .backend_version = backend_version,
            .backend_stability = .experimental,
            .operator = swap.operator,
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
            .replacement = swap.replacement,
            .expected_compile = .compiles,
            .equivalent_risks = swap.risks,
        });
    }

    return .{
        .candidates = try collector.finish(),
        .diagnostics = try diagnostics.toOwnedSlice(arena),
    };
}

/// True when config opts the named backend into the experimental set.
pub fn backendOptedIn(cfg: config.Config, name: []const u8) bool {
    for (cfg.backend_experimental) |b| {
        if (std.mem.eql(u8, b, name)) return true;
    }
    return false;
}

pub const BackendError = error{ ExperimentalBackendNotEnabled, BackendNotImplemented } || std.mem.Allocator.Error;

/// Gate and build an experimental backend listing from an already-generated AST
/// candidate set. `zir` is owned by task 056 and requires explicit config opt-in
/// (`backend.experimental` contains `zir`), else `error.ExperimentalBackendNotEnabled`.
/// `air` is owned by task 057 and is `error.BackendNotImplemented` here. The
/// stable AST default never routes through this gate.
pub fn experimentalListing(
    arena: std.mem.Allocator,
    cfg: config.Config,
    ast_candidates: []const mutant.Mutant,
    backend: []const u8,
) BackendError!Result {
    if (!std.mem.eql(u8, backend, "zir")) return error.BackendNotImplemented;
    if (!backendOptedIn(cfg, "zir")) return error.ExperimentalBackendNotEnabled;
    return fromAst(arena, ast_candidates);
}

/// The out-of-report diagnostics artifact (a separate schema, never report v1).
/// Intended for a task-scoped on-disk file under
/// artifacts/pipeline/<task-id>/experimental-backend-diagnostics/, but that write
/// is not yet implemented -- the serializer below is ready and tested for it (L25).
const DiagnosticsArtifact = struct {
    schema_version: []const u8 = "zentinel.experimental_backend_diagnostics.v1",
    backend: []const u8 = "zir",
    backend_stability: []const u8 = "experimental",
    zig_version: []const u8 = "0.16.0",
    unsupported: []const Diagnostic,
};

/// Serialize the unsupported-operator diagnostics to deterministic JSON for the
/// out-of-report task-scoped artifact. Ready and byte-pinned by tests, but NOT
/// yet wired to an on-disk write: at CLI runtime these diagnostics are surfaced
/// as stderr `note[...]` lines, not this artifact (L25).
pub fn diagnosticsToJson(arena: std.mem.Allocator, diagnostics: []const Diagnostic) std.mem.Allocator.Error![]u8 {
    const artifact = DiagnosticsArtifact{ .unsupported = diagnostics };
    return std.json.Stringify.valueAlloc(arena, artifact, .{ .whitespace = .indent_2 });
}

/// The human-facing stderr `note[...]` line for one out-of-report diagnostic --
/// the CLI surface for unsupported operators. Kept here (not inline in cli.zig)
/// so the note format is directly testable rather than only reachable end-to-end
/// through the binary (L26).
pub fn renderDiagnosticNote(arena: std.mem.Allocator, d: Diagnostic) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(arena, "note[{s}]: {s} at {s}:{d}..{d} ({s})\n", .{ d.code, d.operator, d.file, d.span_start, d.span_end, d.reason });
}
