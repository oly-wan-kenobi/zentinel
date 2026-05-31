// Layer: deterministic_core
//
// Test selection (docs/TEST_SELECTION.md): the default `same_file_then_package`
// strategy prefers a generated `zig test <file>` command for a mutated file and
// falls back to the configured package/build commands. Pure: it decides the
// selection from discovered same-file tests, the configured commands, and an
// (already-executed) preflight result; the preflight itself is run by the
// orchestrator/adapter. Selection never uses AI and never hides a mutant from
// the report (I-012).
const std = @import("std");
const report = @import("report.zig");
const ast_backend = @import("ast_backend.zig");

pub const Strategy = report.Strategy;

/// Discover the same-file tests for a parsed file, as report SelectedTests sorted
/// deterministically by file, line, then name.
pub fn sameFileTests(arena: std.mem.Allocator, parsed: ast_backend.Parsed, file: []const u8) std.mem.Allocator.Error![]report.SelectedTest {
    const decls = try ast_backend.testDecls(parsed, arena);
    var list: std.ArrayList(report.SelectedTest) = .empty;
    for (decls) |d| {
        try list.append(arena, .{ .file = file, .name = d.name, .line = d.line });
    }
    const items = try list.toOwnedSlice(arena);
    std.mem.sort(report.SelectedTest, items, {}, lessSelected);
    return items;
}

fn lessSelected(_: void, a: report.SelectedTest, b: report.SelectedTest) bool {
    switch (std.mem.order(u8, a.file, b.file)) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    }
    if (a.line != b.line) return a.line < b.line;
    return std.mem.lessThan(u8, a.name, b.name);
}

/// The generated same-file command for a file: `zig test <file>`.
pub fn generatedCommand(arena: std.mem.Allocator, file: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(arena, "zig test {s}", .{file});
}

pub const Resolution = struct {
    /// Report metadata for this mutant's selection.
    selection: report.TestSelection,
    /// The commands to actually run for the mutant.
    commands: []const []const u8,
};

/// Resolve the selection for one mutated file. `preflight` is the result of
/// running the generated command against the unmutated project (null when no
/// generated command was run, e.g. it was already a baseline command, or the
/// file has no same-file tests). `generated_in_baseline` is true when the
/// generated command is already in the configured baseline set and so needs no
/// separate preflight.
pub fn resolve(
    arena: std.mem.Allocator,
    strategy: Strategy,
    file: []const u8,
    same_file_tests: []const report.SelectedTest,
    configured_commands: []const []const u8,
    preflight: ?report.CommandResult,
    generated_in_baseline: bool,
) std.mem.Allocator.Error!Resolution {
    // impact_graph uses the same-file tests as the deterministic impact set and,
    // when that set is not already covered, falls back conservatively to the
    // configured suite -- the same machinery as same_file_then_package.
    const same_file_enabled = strategy == .same_file or strategy == .same_file_then_package or strategy == .impact_graph;

    if (same_file_enabled and same_file_tests.len > 0) {
        const preflight_passed = if (preflight) |p| p.status == .passed else false;
        if (generated_in_baseline or preflight_passed) {
            const generated = try generatedCommand(arena, file);
            const commands = try arena.dupe([]const u8, &.{generated});
            const preflights: []const report.CommandResult = if (generated_in_baseline)
                &.{}
            else
                try arena.dupe(report.CommandResult, &.{preflight.?});
            return .{
                .selection = .{
                    .strategy = strategy,
                    .selected = same_file_tests,
                    .commands = commands,
                    .preflight_commands = preflights,
                    .fallback_used = false,
                },
                .commands = commands,
            };
        }
        // Same-file tests exist but the generated command failed its preflight:
        // record the evidence and fall back to the configured commands.
        const preflights: []const report.CommandResult = if (preflight) |p|
            try arena.dupe(report.CommandResult, &.{p})
        else
            &.{};
        return .{
            .selection = .{
                .strategy = strategy,
                .selected = same_file_tests,
                .commands = configured_commands,
                .preflight_commands = preflights,
                .fallback_used = true,
            },
            .commands = configured_commands,
        };
    }

    // `all`/`package` run the configured commands directly; a same-file strategy
    // with no discovered tests falls back to them.
    return .{
        .selection = .{
            .strategy = strategy,
            .selected = &.{},
            .commands = configured_commands,
            .preflight_commands = &.{},
            .fallback_used = same_file_enabled,
        },
        .commands = configured_commands,
    };
}
