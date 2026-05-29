//! Fixture system for zentinel mutation tests (task 004).
//!
//! Test-support loader (not a `src/` architecture layer) that enumerates
//! fixture projects under `test/fixtures/projects` and reads their
//! `fixture.toml` metadata via the in-tree TOML subset parser re-exported from
//! the `zentinel` module hub (ADR-0009). No mutant generation happens here;
//! fixtures are Stage 1 dogfood inputs for the future mutation engine.
const std = @import("std");
const zentinel = @import("zentinel");
const harness = @import("harness.zig");

const toml = zentinel.config_toml;

/// Project-relative root under which each fixture project lives in its own
/// directory containing a `fixture.toml`.
pub const projects_root = "test/fixtures/projects";

/// TOML diagnostic surfaced by the underlying parser; re-exported so tests do
/// not need to import the config parser directly.
pub const Diagnostic = toml.Diagnostic;

/// Headline expected result of running zentinel against a fixture. The mutant
/// outcomes mirror the report v1 summary vocabulary
/// (schemas/report.v1.schema.json); `no_eligible_sources` is the project-level
/// outcome for failure mode F-006 (analysis fails before mutation generation).
pub const ExpectedOutcome = enum {
    killed,
    survived,
    compile_error,
    compiler_crash,
    timeout,
    skipped,
    invalid,
    no_eligible_sources,

    pub fn parse(text: []const u8) ?ExpectedOutcome {
        return std.meta.stringToEnum(ExpectedOutcome, text);
    }
};

/// One enumerated fixture project: its directory name and normalized
/// project-relative path.
pub const FixtureRef = struct {
    name: []const u8,
    path: []const u8,
};

/// Validated fixture metadata parsed from `fixture.toml`.
pub const FixtureMeta = struct {
    name: []const u8,
    description: []const u8,
    target_files: []const []const u8,
    test_command: []const u8,
    expected_operators: []const []const u8,
    expected_outcome: ExpectedOutcome,
};

/// Errors specific to fixture metadata interpretation, layered on the TOML
/// parser's error set.
pub const MetaError = error{InvalidFixtureMetadata} || toml.ParseError;

/// Upper bound on a `fixture.toml` read. Fixture metadata is intentionally tiny.
const read_limit = std.Io.Limit.limited(1 << 20);

/// Enumerate fixture projects under `projects_root`, sorted by normalized
/// project-relative path. Sorting makes discovery deterministic regardless of
/// raw filesystem iteration order. Allocates into `arena`.
pub fn discover(io: std.Io, arena: std.mem.Allocator) ![]FixtureRef {
    var dir = try std.Io.Dir.cwd().openDir(io, projects_root, .{ .iterate = true });
    defer dir.close(io);

    var refs: std.ArrayList(FixtureRef) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        // entry.name is only valid until the next iteration; copy it now.
        const name = try arena.dupe(u8, entry.name);
        const raw = try std.fmt.allocPrint(arena, "{s}/{s}", .{ projects_root, name });
        const path = try harness.normalizePath(arena, raw, "");
        try refs.append(arena, .{ .name = name, .path = path });
    }

    std.mem.sort(FixtureRef, refs.items, {}, lessByPath);
    return refs.toOwnedSlice(arena);
}

fn lessByPath(_: void, a: FixtureRef, b: FixtureRef) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

/// Read and validate the `fixture.toml` for a discovered fixture.
pub fn loadMeta(io: std.Io, arena: std.mem.Allocator, ref: FixtureRef, diag: *Diagnostic) !FixtureMeta {
    const toml_path = try std.fmt.allocPrint(arena, "{s}/fixture.toml", .{ref.path});
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, toml_path, arena, read_limit);
    return parseMeta(arena, bytes, diag);
}

/// Parse and validate fixture metadata from TOML text. Pure: no filesystem
/// access, so it is the deterministic core of metadata validation and is the
/// surface tested with both valid and invalid in-memory inputs.
pub fn parseMeta(arena: std.mem.Allocator, source: []const u8, diag: *Diagnostic) MetaError!FixtureMeta {
    const doc = try toml.parse(arena, source, diag);

    const name = findString(doc, "fixture", "name") orelse return error.InvalidFixtureMetadata;
    if (name.len == 0) return error.InvalidFixtureMetadata;
    const description = findString(doc, "fixture", "description") orelse return error.InvalidFixtureMetadata;
    const test_command = findString(doc, "project", "test_command") orelse return error.InvalidFixtureMetadata;
    if (test_command.len == 0) return error.InvalidFixtureMetadata;
    const target_files = findArray(doc, "project", "target_files") orelse return error.InvalidFixtureMetadata;
    const operators = findArray(doc, "expect", "operators") orelse return error.InvalidFixtureMetadata;
    const outcome_text = findString(doc, "expect", "outcome") orelse return error.InvalidFixtureMetadata;
    const outcome = ExpectedOutcome.parse(outcome_text) orelse return error.InvalidFixtureMetadata;

    // A mutation fixture must name at least one target source unless its whole
    // point is that there are no eligible sources (F-006).
    if (outcome == .no_eligible_sources) {
        if (target_files.len != 0) return error.InvalidFixtureMetadata;
    } else {
        if (target_files.len == 0) return error.InvalidFixtureMetadata;
    }

    return .{
        .name = name,
        .description = description,
        .target_files = target_files,
        .test_command = test_command,
        .expected_operators = operators,
        .expected_outcome = outcome,
    };
}

/// Join a fixture-relative source path onto the fixture's project-relative path,
/// normalized to forward slashes. Never produces an absolute path.
pub fn targetPath(arena: std.mem.Allocator, ref: FixtureRef, target_file: []const u8) ![]const u8 {
    const raw = try std.fmt.allocPrint(arena, "{s}/{s}", .{ ref.path, target_file });
    return harness.normalizePath(arena, raw, "");
}

/// Normalize a path to a forward-slashed, project-relative form, stripping
/// `abs_root` when present. Reuses the shared harness normalizer so fixture and
/// report snapshots share one normalization contract.
pub fn normalizePath(arena: std.mem.Allocator, text: []const u8, abs_root: []const u8) ![]const u8 {
    return harness.normalizePath(arena, text, abs_root);
}

fn findString(doc: toml.Document, section: []const u8, key: []const u8) ?[]const u8 {
    for (doc.entries) |entry| {
        if (std.mem.eql(u8, entry.section, section) and std.mem.eql(u8, entry.key, key)) {
            return switch (entry.value) {
                .string => |s| s,
                else => null,
            };
        }
    }
    return null;
}

fn findArray(doc: toml.Document, section: []const u8, key: []const u8) ?[]const []const u8 {
    for (doc.entries) |entry| {
        if (std.mem.eql(u8, entry.section, section) and std.mem.eql(u8, entry.key, key)) {
            return switch (entry.value) {
                .string_array => |arr| arr,
                else => null,
            };
        }
    }
    return null;
}
