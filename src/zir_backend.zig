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
