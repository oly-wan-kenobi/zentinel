// Layer: deterministic_core
//
// Experimental ZIR backend prototype (docs/ZIR_BACKEND.md). The ZIR backend is
// disabled by default and reachable only through explicit config or CLI opt-in.
// The ZIR backend really lowers each source file to ZIR via `std.zig.AstGen`
// (`fromTree`/`listFromTrees`) and recognizes binary-operator mutation sites --
// comparison, short-circuit logical, and arithmetic -- from the instructions ZIR
// emits, mapping each back to its exact AST node and tagging it `backend = .zir`,
// `backend_stability = .experimental`. There is one code path: the legacy relabel
// adapter has been retired (ZIR-4). Operators ZIR does not represent as a single
// instruction (literal and control-flow rewrites) are NOT emitted as mutants; they
// become out-of-report backend diagnostics so they never affect mutation score,
// survivor counts, or report v1 fields. Post-Sema (AIR) semantic analysis is out of
// scope here: report v1 stays closed. At CLI runtime the unsupported evidence is
// surfaced as stderr `note[...]` lines (src/cli.zig); the schema-versioned
// on-disk artifact (`diagnosticsToJson` -> zentinel.experimental_backend_diagnostics.v1,
// intended under artifacts/pipeline/<task-id>/experimental-backend-diagnostics/)
// is defined and tested but its pipeline write is not yet implemented (L25).
// Targets pinned Zig 0.16.0; the version-coupled `src_node` decoding is guarded by
// `toolchainSupported` -- `listFromTrees` declines (error.UnsupportedZigVersion) on
// any other toolchain (3a). `differentialOracle` cross-checks the ZIR set against the
// AST recognizers, and `fromTree` audits that instructions resolve to a bijection over
// distinct AST nodes, flagging collisions as out-of-report anomalies (3c).
const std = @import("std");
const mutant = @import("mutant.zig");
const config = @import("config.zig");
const ast_backend = @import("ast_backend.zig");
const source_map = @import("source_map.zig");
const run_command = @import("run_command.zig");
const zig_version = @import("zig_version.zig");

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

/// Which recognizer saw a binary-operator mutation site the other missed.
/// `zir_only`: ZIR lowered a site the AST recognizers did not produce. `ast_only`:
/// the AST recognizers produced a binary-operator candidate ZIR did not lower.
pub const DivergenceSide = enum { zir_only, ast_only };

/// One `(operator, span)` the ZIR and AST binary-operator recognizers disagree on,
/// found by `differentialOracle`. It is a correctness signal about the recognizers,
/// never a mutant and never a report v1 field.
pub const Divergence = struct {
    file: []const u8,
    operator: []const u8,
    span_start: u64,
    span_end: u64,
    side: DivergenceSide,
};

// --- Real ZIR lowering (task 056) -------------------------------------------
//
// `fromTree` lowers the source to ZIR via `std.zig.AstGen` and recognizes
// binary-operator mutation sites from the instructions ZIR emits -- `cmp_*`,
// `bool_br_and`/`bool_br_or`, and `add`/`sub`/`mul`/`div` -- mapping each back to
// its exact AST node. Candidate metadata mirrors the AST recognizers
// (src/mutators/{comparison,logical,arithmetic}.zig) so the two backends stay in
// differential parity -- the zir_backend parity test pins this. ZIR's real
// contributions: dropping AstGen-injected operators (for-bounds, switch ranges)
// that have no source operator, and comptime-context-aware `expected_compile`.
// Source mapping: `pl_node.src_node` is an offset from the enclosing declaration
// node, so the operator node `n` is the one whose `n - off` is itself a decl base
// (innermost wins); injected operators resolve to none.

pub const FromTreeError = error{BackendParseError} || std.mem.Allocator.Error;

/// The single AST node tag a recognized ZIR instruction maps back to. `cmp_*`
/// (comparison operators) and `bool_br_and`/`bool_br_or` (short-circuit `and`/`or`)
/// all carry a decl-relative `pl_node.src_node`, so the source node is recovered the
/// same way for every supported operator. (Boolean literals are intentionally absent:
/// `true`/`false` lower to operand refs, not instructions -- see listFromTrees.)
fn expectedAstTag(t: std.zig.Zir.Inst.Tag) ?std.zig.Ast.Node.Tag {
    return switch (t) {
        .cmp_eq => .equal_equal,
        .cmp_neq => .bang_equal,
        .cmp_lt => .less_than,
        .cmp_lte => .less_or_equal,
        .cmp_gt => .greater_than,
        .cmp_gte => .greater_or_equal,
        .bool_br_and => .bool_and,
        .bool_br_or => .bool_or,
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .div,
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

/// Outcome of resolving a `pl_node` instruction to its source AST node.
const Resolution = union(enum) {
    /// The instruction's source node (tag `want`); the caller claims it.
    node: u32,
    /// At least one node of tag `want` has a valid decl base for this offset, but every
    /// such node is already claimed -- a genuine over-subscription the claim-aware pass
    /// could not place. The 3c residual guard fires here (does not occur on real code).
    exhausted,
    /// No node of tag `want` has a valid decl base for this offset: the instruction is
    /// AstGen-injected (for-bounds / switch range / etc.) with no source operator.
    none,
};

/// Resolve a `pl_node` instruction to its source AST node of tag `want`, claim-aware:
/// among the nodes whose `n - off` is a declaration base, return the innermost (largest
/// such base) one that is NOT yet `claimed`. Two same-operator sites at equal
/// decl-relative offsets thus resolve to distinct nodes -- the first takes the innermost
/// decl, the second the next -- recovering the site the old innermost-only heuristic
/// dropped (ZIR-5). `.none` is an injected instruction (no candidate node); `.exhausted`
/// means candidate nodes exist but are all claimed.
fn resolveNode(tree: std.zig.Ast, is_base: []const bool, claimed: []const bool, want: std.zig.Ast.Node.Tag, off: i32, node_count: i64) Resolution {
    const node_tags = tree.nodes.items(.tag);
    var best: ?u32 = null;
    var best_base: i64 = -1;
    var any_candidate = false;
    var i: u32 = 0;
    while (i < node_count) : (i += 1) {
        if (node_tags[i] != want) continue;
        const base: i64 = @as(i64, i) - off;
        if (base < 0 or base >= node_count) continue;
        if (!is_base[@intCast(base)]) continue;
        any_candidate = true; // a real source node exists for this offset
        if (claimed[i]) continue; // ...but it is already taken by another instruction
        if (base > best_base) {
            best = i;
            best_base = base;
        }
    }
    if (best) |n| return .{ .node = n };
    if (any_candidate) return .exhausted;
    return .none;
}

/// A half-open source byte range `[start, end)`.
const ByteRange = struct { start: u32, end: u32 };

/// Source byte-spans of the `comptime { ... }` regions in `tree`, confirmed against
/// the ZIR `block_comptime` instructions AstGen emits for comptime-forced code. This
/// is the one comptime signal recoverable in process from the public `Zir`: the AST
/// records the `comptime` keyword, but only AstGen decides which regions it actually
/// comptime-forces.
///
/// A `block_comptime`'s `src_node` is a decl-relative offset, like every `pl_node`.
/// Rather than resolve each instruction to a single node -- which mis-resolves when
/// two comptime blocks share an offset, since the innermost-base heuristic collapses
/// them onto one node -- we enumerate the unambiguous `.@"comptime"` AST nodes and
/// confirm each: a node is comptime-forced iff some `block_comptime` offset places it
/// on a declaration base. Same-offset blocks are then each confirmed independently.
///
/// Out of scope (left at the AST recognizers' runtime-context bucket): implicit
/// comptime contexts (container const initializers, array lengths) emit no
/// `block_comptime`, and the `comptime var` / inherited-comptime-block forms anchor
/// `block_comptime` to a non-`.@"comptime"` node. A missed region only forgoes the
/// refinement; it never mislabels a runtime site.
fn comptimeBlockSpans(
    arena: std.mem.Allocator,
    tree: std.zig.Ast,
    is_base: []const bool,
    inst_tags: []const std.zig.Zir.Inst.Tag,
    inst_datas: []const std.zig.Zir.Inst.Data,
    node_count: i64,
) std.mem.Allocator.Error![]ByteRange {
    var spans: std.ArrayList(ByteRange) = .empty;

    // Decl-relative offsets carried by the ZIR block_comptime instructions.
    var offsets: std.ArrayList(i32) = .empty;
    for (inst_tags, 0..) |t, i| {
        if (t == .block_comptime) try offsets.append(arena, @intFromEnum(inst_datas[i].pl_node.src_node));
    }
    if (offsets.items.len == 0) return spans.toOwnedSlice(arena);

    const node_tags = tree.nodes.items(.tag);
    var n: u32 = 0;
    while (n < node_count) : (n += 1) {
        if (node_tags[n] != .@"comptime") continue;
        // Confirm against ZIR: some block_comptime offset must place this comptime
        // node on a declaration base (the offsets are measured from the decl base).
        var confirmed = false;
        for (offsets.items) |off| {
            const base: i64 = @as(i64, n) - off;
            if (base >= 0 and base < node_count and is_base[@intCast(base)]) {
                confirmed = true;
                break;
            }
        }
        if (!confirmed) continue;
        const ni: std.zig.Ast.Node.Index = @enumFromInt(n);
        const first = tree.tokenStart(tree.firstToken(ni));
        const last_tok = tree.lastToken(ni);
        const end = tree.tokenStart(last_tok) + @as(u32, @intCast(tree.tokenSlice(last_tok).len));
        try spans.append(arena, .{ .start = first, .end = end });
    }
    return spans.toOwnedSlice(arena);
}

/// True when source byte `byte` falls inside any comptime block span.
fn inComptimeSpan(spans: []const ByteRange, byte: u32) bool {
    for (spans) |s| {
        if (byte >= s.start and byte < s.end) return true;
    }
    return false;
}

/// Comptime evaluation is strict: a binary-operator swap that compiles at runtime can
/// surface a *compile* error when comptime-evaluated (a `@compileError` path, a
/// comptime-only bound, or a comptime type mismatch the runtime path would defer), so
/// a `.compiles` site is downgraded to `.may_fail` inside a comptime block. Already
/// uncertain buckets (arithmetic's `.may_fail`, and `.must_fail`) are left unchanged.
fn comptimeAwareCompile(e: mutant.ExpectedCompile) mutant.ExpectedCompile {
    return switch (e) {
        .compiles => .may_fail,
        .may_fail => .may_fail,
        .must_fail => .must_fail,
    };
}

// Operator metadata mirrored from src/mutators/comparison.zig and logical.zig (files
// this task may not modify). The parity test guarantees these stay equivalent to the
// AST recognizers; a drift surfaces as a parity failure, not a silent divergence.
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
const logical_risks = [_][]const u8{
    "one operand constant",
    "guards where later code makes branches equivalent",
    "tests not covering short-circuit side effects",
};
// Arithmetic carries no equivalent_risks and `expected_compile = .may_fail` (an
// unsigned/comptime swap can fail to compile without type info) -- mirrored from
// src/mutators/arithmetic.zig, unlike comparison/logical which `.compiles`.
const no_risks = [_][]const u8{};
const Mutation = struct {
    operator: []const u8,
    replacement: []const u8,
    risks: []const []const u8,
    expected_compile: mutant.ExpectedCompile,
};

fn mutationFor(tag: std.zig.Ast.Node.Tag) ?Mutation {
    return switch (tag) {
        .equal_equal => .{ .operator = "equality_swap", .replacement = "!=", .risks = &equality_risks, .expected_compile = .compiles },
        .bang_equal => .{ .operator = "equality_swap", .replacement = "==", .risks = &equality_risks, .expected_compile = .compiles },
        .less_than => .{ .operator = "comparison_boundary", .replacement = "<=", .risks = &boundary_risks, .expected_compile = .compiles },
        .less_or_equal => .{ .operator = "comparison_boundary", .replacement = "<", .risks = &boundary_risks, .expected_compile = .compiles },
        .greater_than => .{ .operator = "comparison_boundary", .replacement = ">=", .risks = &boundary_risks, .expected_compile = .compiles },
        .greater_or_equal => .{ .operator = "comparison_boundary", .replacement = ">", .risks = &boundary_risks, .expected_compile = .compiles },
        .bool_and => .{ .operator = "logical_and_or", .replacement = "or", .risks = &logical_risks, .expected_compile = .compiles },
        .bool_or => .{ .operator = "logical_and_or", .replacement = "and", .risks = &logical_risks, .expected_compile = .compiles },
        .add => .{ .operator = "arithmetic_add_sub", .replacement = "-", .risks = &no_risks, .expected_compile = .may_fail },
        .sub => .{ .operator = "arithmetic_add_sub", .replacement = "+", .risks = &no_risks, .expected_compile = .may_fail },
        .mul => .{ .operator = "arithmetic_mul_div", .replacement = "/", .risks = &no_risks, .expected_compile = .may_fail },
        .div => .{ .operator = "arithmetic_mul_div", .replacement = "*", .risks = &no_risks, .expected_compile = .may_fail },
        else => null,
    };
}

fn isNullToken(tree: std.zig.Ast, tok: u32) bool {
    if (tok >= tree.tokens.len) return false;
    return std.mem.eql(u8, tree.tokenSlice(tok), "null");
}

/// Lower `source` to ZIR and emit the experimental ZIR candidate set for the
/// binary-operator mutations ZIR represents as a single instruction: comparison
/// (`equality_swap`, `comparison_boundary`), short-circuit logical (`logical_and_or`),
/// and arithmetic (`arithmetic_add_sub`, `arithmetic_mul_div`). Candidates are
/// byte-for-byte the AST recognizers', re-tagged `backend = .zir`; AstGen-injected
/// arithmetic/comparisons (for-bounds, array indexing, switch ranges) become
/// out-of-report diagnostics, never mutants. The one refinement over the AST set:
/// a candidate inside a `comptime { ... }` block (located via the ZIR `block_comptime`
/// instructions) carries a comptime-aware `expected_compile` -- `.compiles` is
/// downgraded to `.may_fail` because comptime evaluation is strict.
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

    // Comptime-forced regions (from the ZIR `block_comptime` instructions): an
    // operator inside one is comptime-evaluated, where evaluation is strict.
    const comptime_spans = try comptimeBlockSpans(arena, tree, is_base, inst_tags, inst_datas, node_count);

    var collector = ast_backend.Collector.init(arena);
    var diagnostics: std.ArrayList(Diagnostic) = .empty;

    // Claim-aware resolution + 3c audit: `claimed[n]` records that node `n` has been
    // resolved to, so the next instruction at the same decl-relative offset takes the
    // next-innermost node instead of colliding onto it (ZIR-5). A genuine
    // over-subscription -- candidate nodes all claimed -- surfaces as a residual anomaly.
    const claimed = try arena.alloc(bool, tree.nodes.len);
    @memset(claimed, false);

    for (inst_tags, 0..) |t, i| {
        const want = expectedAstTag(t) orelse continue;
        const off = @intFromEnum(inst_datas[i].pl_node.src_node);
        const n = switch (resolveNode(tree, is_base, claimed, want, off, node_count)) {
            .node => |nn| nn,
            .none => {
                // AstGen-injected comparison (for-bounds / switch range): no source
                // operator, so it is an out-of-report diagnostic, never a mutant.
                try diagnostics.append(arena, .{
                    .file = file,
                    .operator = "injected",
                    .span_start = 0,
                    .span_end = 0,
                    .reason = "ZIR instruction with no source operator (compiler-injected bounds/range check)",
                });
                continue;
            },
            .exhausted => {
                // 3c residual guard: candidate nodes existed for this offset but were
                // all claimed by other instructions -- a non-bijective mapping the
                // claim-aware resolver could not place. Does not occur on real code (the
                // src/ audit is zero); surface it rather than silently dropping a site.
                try diagnostics.append(arena, .{
                    .code = "ZNTL_ZIR_RESOLUTION_ANOMALY",
                    .file = file,
                    .operator = "resolution_anomaly",
                    .span_start = 0,
                    .span_end = 0,
                    .reason = "ZIR instruction's candidate AST nodes were all claimed by other instructions (non-bijective mapping the claim-aware resolver could not place)",
                });
                continue;
            },
        };
        claimed[n] = true;
        const node: std.zig.Ast.Node.Index = @enumFromInt(n);
        const mut = mutationFor(node_tags[n]) orelse continue; // resolveNode guarantees a supported tag
        const op_tok = tree.nodeMainToken(node);
        const op_start = tree.tokenStart(op_tok);
        // Parity with the AST recognizers: skip operators inside test bodies, and
        // leave `x == null` / `null == x` to optional_null_check.
        if (ast_backend.inTestBody(test_ranges, op_start)) continue;
        if (std.mem.eql(u8, mut.operator, "equality_swap")) {
            const right_null = isNullToken(tree, op_tok + 1);
            const left_null = op_tok > 0 and isNullToken(tree, op_tok - 1);
            if (right_null or left_null) continue;
        }
        const op_text = tree.tokenSlice(op_tok);
        const op_end = op_start + @as(u32, @intCast(op_text.len));
        const start_pos = source_map.locate(tree.source, op_start) orelse continue;
        const end_pos = source_map.locate(tree.source, op_end) orelse continue;
        // The one refinement ZIR adds over the AST recognizers: a site inside a
        // comptime block gets a comptime-aware `expected_compile` (strict evaluation),
        // not the AST's runtime-context bucket.
        const expected_compile = if (inComptimeSpan(comptime_spans, op_start))
            comptimeAwareCompile(mut.expected_compile)
        else
            mut.expected_compile;
        try collector.add(.{
            .id = "",
            .backend = .zir,
            .backend_version = backend_version,
            .backend_stability = .experimental,
            .operator = mut.operator,
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
            .replacement = mut.replacement,
            .expected_compile = expected_compile,
            .equivalent_risks = mut.risks,
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

pub const ListError = error{ ExperimentalBackendNotEnabled, BackendNotImplemented, BackendParseError, UnsupportedZigVersion } || std.mem.Allocator.Error;

/// 3a version guard: the ZIR path decodes `pl_node.src_node` offsets whose meaning is
/// coupled to the exact Zig version (`backend_version` pins zig-0.16.0) -- a different
/// toolchain shifts AstGen's node/instruction layout and would silently mis-resolve.
/// True only when the discovered toolchain is exactly the pinned `supported_version`;
/// `listFromTrees` declines with `error.UnsupportedZigVersion` otherwise. Pure and
/// injectable: the adapter discovers the version, this classifies it.
pub fn toolchainSupported(discovery: zig_version.Discovery) bool {
    return zig_version.classify(discovery) == .supported;
}

/// Operators the ZIR backend lowers to real candidates (those ZIR represents as a
/// single instruction): the binary-operator mutations -- comparison, short-circuit
/// logical, and arithmetic (Phases 1-3). Literal and control-flow operators are
/// AST-only by principle (see listFromTrees / docs/ZIR_BACKEND.md).
fn isZirLoweredOperator(op: []const u8) bool {
    return std.mem.eql(u8, op, "equality_swap") or
        std.mem.eql(u8, op, "comparison_boundary") or
        std.mem.eql(u8, op, "logical_and_or") or
        std.mem.eql(u8, op, "arithmetic_add_sub") or
        std.mem.eql(u8, op, "arithmetic_mul_div");
}

/// Build the experimental ZIR listing by REALLY lowering each source file to ZIR
/// (`fromTree`), not relabeling the AST candidate set. Comparison operators become
/// genuine ZIR candidates; every other AST operator (not yet ZIR-lowered in Phase 1)
/// and every AstGen-injected comparison becomes an out-of-report diagnostic, so a
/// previously-listed operator is never silently dropped. Requires `backend.experimental`
/// to contain `zir` and the discovered toolchain `zig` to be the pinned Zig version
/// (3a `toolchainSupported`). This is the path `list-mutants --backend zir` uses.
pub fn listFromTrees(
    arena: std.mem.Allocator,
    cfg: config.Config,
    zig: zig_version.Discovery,
    files: []const run_command.FileSource,
    ast_candidates: []const mutant.Mutant,
    backend: []const u8,
) ListError!Result {
    if (!std.mem.eql(u8, backend, "zir")) return error.BackendNotImplemented;
    if (!backendOptedIn(cfg, "zir")) return error.ExperimentalBackendNotEnabled;
    // 3a: the version-coupled src_node decoding only holds on the pinned toolchain.
    if (!toolchainSupported(zig)) return error.UnsupportedZigVersion;

    var candidates: std.ArrayList(mutant.Mutant) = .empty;
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    for (files) |f| {
        const r = try fromTree(arena, f.path, f.source);
        try candidates.appendSlice(arena, r.candidates);
        try diagnostics.appendSlice(arena, r.diagnostics);
    }
    // Operators the ZIR backend does not lower are surfaced as out-of-report
    // diagnostics rather than silently omitted. `boolean_literal` is a principled
    // boundary, not a TODO: `true`/`false` lower to operand refs, never ZIR
    // instructions, so it has no ZIR representation (handled by the AST backend).
    for (ast_candidates) |c| {
        if (isZirLoweredOperator(c.operator)) continue;
        const reason: []const u8 = if (std.mem.eql(u8, c.operator, "boolean_literal"))
            "boolean_literal has no ZIR representation: `true`/`false` lower to operand refs (bool_true/bool_false), not instructions -- it is a lexical mutation handled by the AST backend"
        else
            "operator is not yet lowered by the ZIR backend (lowered: comparison, logical, and arithmetic operators)";
        try diagnostics.append(arena, .{
            .file = c.file,
            .operator = c.operator,
            .span_start = c.span.byte_start,
            .span_end = c.span.byte_end,
            .reason = reason,
        });
    }
    return .{
        .candidates = try mutant.sortAndDedupe(arena, candidates.items),
        .diagnostics = try diagnostics.toOwnedSlice(arena),
    };
}

/// True when two candidates name the same operator at the same byte span -- the key
/// the differential oracle compares the two recognizers on.
fn sameOperatorSpan(a: mutant.Mutant, b: mutant.Mutant) bool {
    return std.mem.eql(u8, a.operator, b.operator) and
        a.span.byte_start == b.span.byte_start and
        a.span.byte_end == b.span.byte_end;
}

fn divergenceLessThan(_: void, a: Divergence, b: Divergence) bool {
    if (a.span_start != b.span_start) return a.span_start < b.span_start;
    if (a.span_end != b.span_end) return a.span_end < b.span_end;
    return std.mem.order(u8, a.operator, b.operator) == .lt;
}

/// Differential correctness oracle: independently lower `source` to ZIR and compare the
/// binary-operator mutation set ZIR recognizes against `ast_candidates` (the AST
/// backend's candidates for the same file, narrowed to the operators ZIR lowers).
/// Every `(operator, byte_start, byte_end)` only one path recognized is returned as a
/// `Divergence`; agreement yields an empty slice. This produces NO mutants -- it is a
/// check that two independent recognizers agree, so a regression in either (an
/// AST-mutator bug, or Zig-version drift in ZIR's version-coupled `src_node` offsets)
/// surfaces as a divergence instead of a silent mutation-score change. Findings are
/// sorted by (span_start, span_end, operator) for a deterministic report.
pub fn differentialOracle(
    arena: std.mem.Allocator,
    file: []const u8,
    source: []const u8,
    ast_candidates: []const mutant.Mutant,
) FromTreeError![]Divergence {
    const zir = try fromTree(arena, file, source);
    var out: std.ArrayList(Divergence) = .empty;

    // zir_only: a site ZIR lowered with no matching AST binary-operator candidate.
    for (zir.candidates) |z| {
        var matched = false;
        for (ast_candidates) |a| {
            if (isZirLoweredOperator(a.operator) and sameOperatorSpan(z, a)) {
                matched = true;
                break;
            }
        }
        if (!matched) try out.append(arena, .{
            .file = file,
            .operator = z.operator,
            .span_start = z.span.byte_start,
            .span_end = z.span.byte_end,
            .side = .zir_only,
        });
    }

    // ast_only: an AST binary-operator candidate ZIR did not lower at that span. Only
    // operators ZIR lowers are in scope -- literal/control-flow operators legitimately
    // have no ZIR candidate (see isZirLoweredOperator) and are not divergences.
    for (ast_candidates) |a| {
        if (!isZirLoweredOperator(a.operator)) continue;
        var matched = false;
        for (zir.candidates) |z| {
            if (sameOperatorSpan(a, z)) {
                matched = true;
                break;
            }
        }
        if (!matched) try out.append(arena, .{
            .file = file,
            .operator = a.operator,
            .span_start = a.span.byte_start,
            .span_end = a.span.byte_end,
            .side = .ast_only,
        });
    }

    std.mem.sort(Divergence, out.items, {}, divergenceLessThan);
    return out.toOwnedSlice(arena);
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
