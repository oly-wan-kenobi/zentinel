// Layer: deterministic_core
//
// Experimental AIR backend prototype (docs/AIR_BACKEND.md). AIR is the
// highest-risk backend (closest to compiler internals); it is disabled by
// default and reachable only through explicit config/CLI opt-in. This prototype
// is a deterministic adapter: it derives AIR candidates from the stable AST
// candidate set so source mapping is exact by construction, re-tagging the
// operators AIR can map exactly (overflow-sensitive arithmetic and bounds
// comparisons) with `backend = .air` and `backend_stability = .experimental`.
// Operators AIR can only map approximately (control-flow boolean/logical forms)
// are NOT emitted as mutants; they become out-of-report diagnostics that carry
// the documented `source_mapping` enum (none/approximate/exact, only `exact`
// enters the mutant list) and the active safety-mode metadata. report v1 stays
// closed (only `backend`/`backend_stability`); all backend-specific evidence is
// out-of-report. At CLI runtime it is surfaced as stderr `note[...]` lines
// (src/cli.zig); the schema-versioned on-disk artifact (`diagnosticsToJson`,
// intended under artifacts/pipeline/<task-id>/experimental-backend-diagnostics/)
// is defined and tested but its pipeline write is not yet implemented (L25).
// Targets pinned Zig 0.16.0; version coupling is handled by opt-in diagnostics.
const std = @import("std");
const mutant = @import("mutant.zig");
const config = @import("config.zig");

/// Internal deterministic backend contract string for the experimental AIR
/// prototype under Zig 0.16.0. Part of durable identity (so an AIR candidate
/// never collides with the AST or ZIR candidate at the same span).
pub const backend_version = "air.v1.zig-0.16.0";

/// Out-of-report AIR backend diagnostic for a candidate AIR cannot map exactly.
/// `source_mapping` is the documented enum (none/approximate/exact); a diagnostic
/// is never `exact`. `safety_mode` is the active Zig mode when available.
pub const Diagnostic = struct {
    code: []const u8 = "ZNTL_AIR_UNSUPPORTED",
    file: []const u8,
    operator: []const u8,
    span_start: u64,
    span_end: u64,
    source_mapping: []const u8,
    safety_mode: []const u8,
    reason: []const u8,
};

pub const Result = struct {
    candidates: []const mutant.Mutant,
    diagnostics: []const Diagnostic,
};

/// Operators AIR can map to an exact source span in the prototype: bounds-check
/// comparisons and overflow-sensitive integer arithmetic (docs/AIR_BACKEND.md
/// mutation areas). Control-flow boolean/logical forms and literal rewrites are
/// only approximately mappable, so they are recorded as diagnostics.
const supported_operators = [_][]const u8{
    "comparison_boundary",
    "equality_swap",
    "arithmetic_add_sub",
    "arithmetic_mul_div",
};

pub fn isSupported(operator: []const u8) bool {
    for (supported_operators) |op| {
        if (std.mem.eql(u8, op, operator)) return true;
    }
    return false;
}

fn reTag(arena: std.mem.Allocator, ast: mutant.Mutant) std.mem.Allocator.Error!mutant.Mutant {
    var c = ast;
    c.backend = .air;
    c.backend_version = backend_version;
    c.backend_stability = .experimental;
    const id = mutant.computeId(c.identity());
    c.id = try arena.dupe(u8, &id);
    return c;
}

/// Build the experimental AIR candidate set from the deterministic AST candidate
/// set. Exactly-mappable operators are re-tagged with source mapping inherited
/// from the AST span; approximately-mappable operators become out-of-report
/// diagnostics (never executable mutants) that record the active safety mode.
pub fn fromAst(arena: std.mem.Allocator, ast_candidates: []const mutant.Mutant, safety_mode: []const u8) std.mem.Allocator.Error!Result {
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
                .source_mapping = "approximate",
                .safety_mode = safety_mode,
                .reason = "operator maps only approximately at the AIR prototype level; only exact mapping may enter the mutant list",
            });
        }
    }
    return .{
        .candidates = try candidates.toOwnedSlice(arena),
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

fn safetyModeOf(cfg: config.Config) []const u8 {
    if (cfg.zig_modes.len > 0) return cfg.zig_modes[0];
    return "Debug";
}

/// Gate and build an experimental AIR listing from an already-generated AST
/// candidate set. `air` requires explicit config opt-in (`backend.experimental`
/// contains `air`), else `error.ExperimentalBackendNotEnabled`. Any other backend
/// is `error.BackendNotImplemented`. The stable AST default never routes here.
pub fn experimentalListing(
    arena: std.mem.Allocator,
    cfg: config.Config,
    ast_candidates: []const mutant.Mutant,
    backend: []const u8,
) BackendError!Result {
    if (!std.mem.eql(u8, backend, "air")) return error.BackendNotImplemented;
    if (!backendOptedIn(cfg, "air")) return error.ExperimentalBackendNotEnabled;
    return fromAst(arena, ast_candidates, safetyModeOf(cfg));
}

/// The out-of-report diagnostics artifact (a separate schema, never report v1).
/// Records the active safety mode and the per-operator approximate mapping.
const DiagnosticsArtifact = struct {
    schema_version: []const u8 = "zentinel.experimental_backend_diagnostics.v1",
    backend: []const u8 = "air",
    backend_stability: []const u8 = "experimental",
    zig_version: []const u8 = "0.16.0",
    safety_mode: []const u8,
    unsupported: []const Diagnostic,
};

/// Serialize the unsupported-operator diagnostics to deterministic JSON. Ready
/// and byte-pinned by tests, but NOT yet wired to an on-disk write: at CLI
/// runtime these diagnostics are surfaced as stderr `note[...]` lines, not this
/// artifact (L25).
pub fn diagnosticsToJson(arena: std.mem.Allocator, diagnostics: []const Diagnostic, safety_mode: []const u8) std.mem.Allocator.Error![]u8 {
    const artifact = DiagnosticsArtifact{ .safety_mode = safety_mode, .unsupported = diagnostics };
    return std.json.Stringify.valueAlloc(arena, artifact, .{ .whitespace = .indent_2 });
}

/// The human-facing stderr `note[...]` line for one out-of-report AIR diagnostic
/// (carries `source_mapping` and the active safety mode) -- the CLI surface for
/// unsupported operators. Kept here (not inline in cli.zig) so the note format is
/// directly testable rather than only reachable end-to-end through the binary (L26).
pub fn renderDiagnosticNote(arena: std.mem.Allocator, d: Diagnostic) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(arena, "note[{s}]: {s} at {s}:{d}..{d} source_mapping={s} mode={s} ({s})\n", .{ d.code, d.operator, d.file, d.span_start, d.span_end, d.source_mapping, d.safety_mode, d.reason });
}
