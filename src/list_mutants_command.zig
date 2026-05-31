// Layer: deterministic_core
//
// `zentinel list-mutants` (docs/CLI_SPEC.md): generate the Phase 1 AST candidate
// set for the discovered source files and render it as a deterministic text or
// JSON listing. Pure and execution-free: it takes source bytes, never an
// executor, so listing candidates can never run a test command or patch a file.
const std = @import("std");
const config = @import("config.zig");
const ast_backend = @import("ast_backend.zig");
const mutant = @import("mutant.zig");
const arithmetic = @import("mutators/arithmetic.zig");
const comparison = @import("mutators/comparison.zig");
const logical = @import("mutators/logical.zig");
const boolean = @import("mutators/boolean.zig");
const optional = @import("mutators/optional.zig");
const error_path = @import("mutators/error_path.zig");
const integer_boundary = @import("mutators/integer_boundary.zig");
const loop_boundary = @import("mutators/loop_boundary.zig");
const run_command = @import("run_command.zig");

/// One eligible source file and its bytes (shared with the run command).
pub const FileSource = run_command.FileSource;

pub const Format = enum { text, json };

pub const Options = struct {
    operator_filter: ?[]const u8 = null,
    format: Format = .text,
};

pub const ParseError = error{ MissingValue, UnknownOption, InvalidFormat };

/// Pure parser for the documented `list-mutants` options.
pub fn parseArgs(args: []const []const u8) ParseError!Options {
    var opts: Options = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--operator")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.operator_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            if (std.mem.eql(u8, args[i], "text")) {
                opts.format = .text;
            } else if (std.mem.eql(u8, args[i], "json")) {
                opts.format = .json;
            } else {
                return error.InvalidFormat;
            }
        } else {
            return error.UnknownOption;
        }
    }
    return opts;
}

fn operatorEnabled(cfg: config.Config, operator: []const u8) bool {
    for (cfg.mutators_enabled) |op| {
        if (std.mem.eql(u8, op, operator)) return true;
    }
    return false;
}

/// Generate the deterministic, deduplicated, canonically-ordered candidate set
/// for the stable AST backend over `files`, keeping only operators enabled in
/// config and matching the optional operator filter. No patching, no execution.
pub fn generate(
    arena: std.mem.Allocator,
    cfg: config.Config,
    files: []const FileSource,
    operator_filter: ?[]const u8,
) std.mem.Allocator.Error![]mutant.Mutant {
    var collector = ast_backend.Collector.init(arena);
    for (files) |f| {
        var parsed = try ast_backend.parse(arena, f.path, f.source);
        defer parsed.deinit();
        if (!parsed.ok()) continue;
        const test_ranges = try ast_backend.testDeclRanges(parsed, arena);
        try arithmetic.collect(&collector, parsed, f.path, test_ranges);
        try comparison.collect(&collector, parsed, f.path, test_ranges);
        try logical.collect(&collector, parsed, f.path, test_ranges);
        try boolean.collect(&collector, parsed, f.path, test_ranges);
        // Phase-2 stable collectors (task 109): kept in lockstep with the run
        // command's generator so `list-mutants` previews exactly the operators a
        // run will emit.
        try optional.collect(&collector, parsed, f.path, test_ranges);
        try error_path.collect(&collector, parsed, f.path, test_ranges);
        try integer_boundary.collect(&collector, parsed, f.path, test_ranges);
        try loop_boundary.collect(&collector, parsed, f.path, test_ranges);
    }
    const all = try collector.finish();

    var kept: std.ArrayList(mutant.Mutant) = .empty;
    for (all) |c| {
        if (!operatorEnabled(cfg, c.operator)) continue;
        if (operator_filter) |op| {
            if (!std.mem.eql(u8, c.operator, op)) continue;
        }
        try kept.append(arena, c);
    }
    return kept.toOwnedSlice(arena);
}

/// Compact, deterministic text listing: one line per candidate plus a count.
pub fn renderText(arena: std.mem.Allocator, candidates: []const mutant.Mutant) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    for (candidates) |m| {
        try out.print(arena, "{s} {s} {s}:{d}:{d} {s} -> {s}\n", .{
            m.id,
            m.operator,
            m.file,
            m.span.line_start,
            m.span.column_start,
            m.original,
            m.replacement,
        });
    }
    try out.print(arena, "{d} mutants\n", .{candidates.len});
    return out.toOwnedSlice(arena);
}

/// JSON listing wrapper. Reuses the shared mutant model fields directly so the
/// durable id, operator, span, and patch text match every other report surface.
const Listing = struct {
    total: usize,
    mutants: []const mutant.Mutant,
};

/// Deterministic, pretty-printed JSON listing of the candidate set.
pub fn renderJson(arena: std.mem.Allocator, candidates: []const mutant.Mutant) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, Listing{ .total = candidates.len, .mutants = candidates }, .{ .whitespace = .indent_2 });
}
