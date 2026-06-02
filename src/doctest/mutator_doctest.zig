// Layer: deterministic_core
//
// Mutator-spec doctest validation (docs/MUTATOR_SPEC.md). It treats a
// `zig before` + `zig after` documentation pair as an executable contract: the
// documented `after` must be exactly what a stable AST mutator produces from
// `before` (all stable operators, Phase 1 and Phase 2). It reuses the real
// candidate generation (no test execution, no
// mutation against assertions) and reports documentation drift when the docs no
// longer match mutator output. Pure and deterministic.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const arithmetic = @import("../mutators/arithmetic.zig");
const comparison = @import("../mutators/comparison.zig");
const logical = @import("../mutators/logical.zig");
const boolean = @import("../mutators/boolean.zig");
const optional = @import("../mutators/optional.zig");
const error_path = @import("../mutators/error_path.zig");
const integer_boundary = @import("../mutators/integer_boundary.zig");
const loop_boundary = @import("../mutators/loop_boundary.zig");
const block = @import("block.zig");
const parser = @import("parser.zig");
const extractor = @import("extractor.zig");
const error_codes = @import("../error_codes.zig");

const doctest_file = "doctest_snippet.zig";

pub const Result = struct {
    matched: bool,
    operator: []const u8,
    candidate_count: usize,
    parse_error: bool = false,
    invalid_candidate: bool = false,
};

pub const PairResult = struct {
    case_id: []const u8,
    file: []const u8,
    line: u32,
    before: []const u8,
    after: []const u8,
    matched: bool,
    operator: []const u8,
};

pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    line: u32,
};

pub const DocValidation = struct {
    pairs: []const PairResult,
    diagnostics: []const Diagnostic,
};

const CandidateSet = union(enum) {
    ok: []mutant.Mutant,
    parse_error,
    invalid_candidate,
};

/// Generate the candidate set from ALL stable AST mutators (Phase 1 and Phase 2)
/// for a parseable Zig snippet. An unparseable snippet yields no candidates.
pub fn candidates(arena: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]mutant.Mutant {
    return switch (try candidatesOrParseError(arena, source)) {
        .ok => |items| items,
        .parse_error => &.{},
        .invalid_candidate => &.{},
    };
}

fn candidatesOrParseError(arena: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!CandidateSet {
    var parsed = ast_backend.parse(arena, doctest_file, source) catch return .parse_error;
    if (!parsed.ok()) return .parse_error;
    var collector = ast_backend.Collector.init(arena);
    const test_ranges = try ast_backend.testDeclRanges(parsed, arena);
    // ALL stable AST collectors, matching the real pipeline (run_command.zig,
    // list_mutants_command.zig). Wiring only the Phase-1 four would make
    // validateDoc falsely report any documented Phase-2 before/after example as
    // drift -- "not produced by any stable mutator" -- even though it is (L24).
    try arithmetic.collect(&collector, parsed, doctest_file, test_ranges);
    try comparison.collect(&collector, parsed, doctest_file, test_ranges);
    try logical.collect(&collector, parsed, doctest_file, test_ranges);
    try boolean.collect(&collector, parsed, doctest_file, test_ranges);
    try optional.collect(&collector, parsed, doctest_file, test_ranges);
    try error_path.collect(&collector, parsed, doctest_file, test_ranges);
    try integer_boundary.collect(&collector, parsed, doctest_file, test_ranges);
    try loop_boundary.collect(&collector, parsed, doctest_file, test_ranges);
    if (collector.invalidCount() > 0) return .invalid_candidate;
    return .{ .ok = try collector.finish() };
}

/// Apply a candidate by replacing its byte span with its replacement. Uses only
/// the candidate's span offsets (into `source`) and its replacement string, so
/// it never depends on the parsed AST lifetime.
fn applyCandidate(arena: std.mem.Allocator, source: []const u8, m: mutant.Mutant) std.mem.Allocator.Error![]const u8 {
    const start: usize = @intCast(m.span.byte_start);
    const end: usize = @intCast(m.span.byte_end);
    if (start > end or end > source.len) return arena.dupe(u8, source);
    return std.fmt.allocPrint(arena, "{s}{s}{s}", .{ source[0..start], m.replacement, source[end..] });
}

/// Does applying some stable Phase 1 mutator candidate to `before` produce
/// `after`? Returns the producing operator when it does. Trailing whitespace is
/// ignored so fenced-block newlines do not defeat a match.
pub fn validatePair(arena: std.mem.Allocator, before: []const u8, after: []const u8) std.mem.Allocator.Error!Result {
    const cands = switch (try candidatesOrParseError(arena, before)) {
        .ok => |items| items,
        .parse_error => return .{ .matched = false, .operator = "", .candidate_count = 0, .parse_error = true },
        .invalid_candidate => return .{ .matched = false, .operator = "", .candidate_count = 0, .invalid_candidate = true },
    };
    const want = std.mem.trim(u8, after, " \t\r\n");
    for (cands) |m| {
        const mutated = try applyCandidate(arena, before, m);
        if (std.mem.eql(u8, std.mem.trim(u8, mutated, " \t\r\n"), want)) {
            return .{ .matched = true, .operator = m.operator, .candidate_count = cands.len };
        }
    }
    return .{ .matched = false, .operator = "", .candidate_count = cands.len };
}

/// Extract every `zig before` + `zig after` pair from a doc and validate each
/// against mutator output. Extraction diagnostics (e.g. a before without an
/// after) and drift diagnostics (a documented transformation no mutator
/// produces) are returned together.
pub fn validateDoc(arena: std.mem.Allocator, file: []const u8, source: []const u8) std.mem.Allocator.Error!DocValidation {
    const parsed = try parser.parse(arena, file, source);
    const extracted = try extractor.extract(arena, file, parsed.blocks, parsed.diagnostics);

    var diags: std.ArrayList(Diagnostic) = .empty;
    for (extracted.diagnostics) |d| {
        try diags.append(arena, .{ .code = d.code, .message = d.message, .line = d.line });
    }

    var pairs: std.ArrayList(PairResult) = .empty;
    for (extracted.cases) |c| {
        if (c.kind != .mutation) continue;
        const before_blk = findBlockByLine(parsed.blocks, c.anchor_line) orelse continue;
        if (c.block_refs.len < 2) continue;
        const after_blk = findBlockByLine(parsed.blocks, lineOfRef(c.block_refs[1])) orelse continue;
        const res = try validatePair(arena, before_blk.content, after_blk.content);
        try pairs.append(arena, .{
            .case_id = c.id,
            .file = c.file,
            .line = c.anchor_line,
            .before = before_blk.content,
            .after = after_blk.content,
            .matched = res.matched,
            .operator = res.operator,
        });
        if (res.parse_error) {
            try diags.append(arena, .{
                .code = "ZNTL_BACKEND_PARSE_ERROR",
                .message = "could not parse mutator-spec before block",
                .line = c.anchor_line,
            });
        } else if (res.invalid_candidate) {
            try diags.append(arena, .{
                .code = "ZNTL_MUTATOR_INVALID_CANDIDATE",
                .message = "mutator generated an invalid candidate for mutator-spec before block",
                .line = c.anchor_line,
            });
        } else if (!res.matched) {
            try diags.append(arena, .{
                .code = error_codes.doctest_snapshot_mismatch,
                .message = "documented transformation is not produced by any stable mutator",
                .line = c.anchor_line,
            });
        }
    }

    return .{ .pairs = try pairs.toOwnedSlice(arena), .diagnostics = try diags.toOwnedSlice(arena) };
}

/// Deterministic drift report for a mismatched before/after pair.
pub fn renderMismatch(arena: std.mem.Allocator, pair: PairResult) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "{s} at {s}:{d} ({s})\n", .{ error_codes.doctest_snapshot_mismatch, pair.file, pair.line, pair.case_id }));
    try out.appendSlice(arena, "documented transformation is not produced by any stable mutator\n");
    try out.appendSlice(arena, "--- before ---\n");
    try out.appendSlice(arena, std.mem.trimEnd(u8, pair.before, "\n"));
    try out.appendSlice(arena, "\n--- documented after ---\n");
    try out.appendSlice(arena, std.mem.trimEnd(u8, pair.after, "\n"));
    try out.appendSlice(arena, "\n");
    return out.toOwnedSlice(arena);
}

fn findBlockByLine(blocks: []const block.Block, line: u32) ?block.Block {
    for (blocks) |b| {
        if (b.line_start == line) return b;
    }
    return null;
}

pub fn lineOfRef(ref: []const u8) u32 {
    // ref is "file:line[:label]"; take the digit run after the first ':'.
    const first = std.mem.indexOfScalar(u8, ref, ':') orelse return 0;
    var end = first + 1;
    while (end < ref.len and ref[end] >= '0' and ref[end] <= '9') : (end += 1) {}
    // Parse with a checked routine, not a hand-rolled `n = n*10 + d` accumulator:
    // an out-of-range or overlong numeric ref resolves to line 0 (which matches no
    // real 1-based anchor) rather than a `panic: integer overflow` (Debug/ReleaseSafe)
    // or a wrapped, wrong line (ReleaseFast). This third copy is brought to parity with
    // the already-hardened lineOfRef in src/doctest_command.zig (M4 / S17).
    return std.fmt.parseInt(u32, ref[first + 1 .. end], 10) catch 0;
}
