const std = @import("std");
const fixture = @import("support/fixture.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

fn indexOfName(refs: []const fixture.FixtureRef, name: []const u8) ?usize {
    for (refs, 0..) |ref, i| {
        if (std.mem.eql(u8, ref.name, name)) return i;
    }
    return null;
}

test "fixture loader enumerates fixture projects deterministically" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const refs = try fixture.discover(std.testing.io, a);
    try expect(refs.len >= 2);

    // Enumeration is sorted by normalized project-relative path, so the order is
    // reproducible across machines regardless of raw directory iteration order.
    var i: usize = 1;
    while (i < refs.len) : (i += 1) {
        try expect(std.mem.lessThan(u8, refs[i - 1].path, refs[i].path));
    }

    const arith = indexOfName(refs, "arithmetic_kill") orelse return error.MissingFixture;
    const none = indexOfName(refs, "no_eligible_sources") orelse return error.MissingFixture;
    try expect(arith < none);

    // Paths are project-relative with forward slashes, never absolute.
    try expectEqualStrings("test/fixtures/projects/arithmetic_kill", refs[arith].path);
    try expect(refs[arith].path[0] != '/');
}

test "fixture metadata names target files, operators, and outcome" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const refs = try fixture.discover(std.testing.io, a);
    const arith = refs[indexOfName(refs, "arithmetic_kill") orelse return error.MissingFixture];
    const none = refs[indexOfName(refs, "no_eligible_sources") orelse return error.MissingFixture];

    var diag: fixture.Diagnostic = .{};
    const meta = try fixture.loadMeta(std.testing.io, a, arith, &diag);
    try expectEqualStrings("arithmetic_kill", meta.name);
    try expectEqual(@as(usize, 1), meta.target_files.len);
    try expectEqualStrings("calc.zig", meta.target_files[0]);
    try expectEqualStrings("zig build test", meta.test_command);
    try expect(meta.expected_operators.len >= 1);
    try expectEqualStrings("arithmetic_add_sub", meta.expected_operators[0]);
    try expectEqual(fixture.ExpectedOutcome.killed, meta.expected_outcome);

    // The no-eligible-sources fixture (F-006) declares zero targets and an
    // expected project-level failure outcome before any mutation generation.
    const none_meta = try fixture.loadMeta(std.testing.io, a, none, &diag);
    try expectEqual(@as(usize, 0), none_meta.target_files.len);
    try expectEqual(fixture.ExpectedOutcome.no_eligible_sources, none_meta.expected_outcome);
}

test "fixture metadata validation rejects invalid metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Unknown expected outcome is rejected deterministically.
    var diag: fixture.Diagnostic = .{};
    const bad_outcome =
        \\[fixture]
        \\name = "x"
        \\description = "d"
        \\[project]
        \\target_files = ["a.zig"]
        \\test_command = "zig build test"
        \\[expect]
        \\operators = ["arithmetic_add_sub"]
        \\outcome = "not_a_real_outcome"
    ;
    try expectError(error.InvalidFixtureMetadata, fixture.parseMeta(a, bad_outcome, &diag));

    // Missing required fields are rejected.
    const missing_outcome =
        \\[fixture]
        \\name = "x"
        \\description = "d"
        \\[project]
        \\target_files = ["a.zig"]
        \\test_command = "zig build test"
    ;
    try expectError(error.InvalidFixtureMetadata, fixture.parseMeta(a, missing_outcome, &diag));

    // A non-empty target set is required unless the outcome is no_eligible_sources.
    const empty_targets =
        \\[fixture]
        \\name = "x"
        \\description = "d"
        \\[project]
        \\target_files = []
        \\test_command = "zig build test"
        \\[expect]
        \\operators = []
        \\outcome = "killed"
    ;
    try expectError(error.InvalidFixtureMetadata, fixture.parseMeta(a, empty_targets, &diag));
}

test "fixture paths normalize to project-relative forward-slash paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ref = fixture.FixtureRef{
        .name = "arithmetic_kill",
        .path = "test/fixtures/projects/arithmetic_kill",
    };
    const target = try fixture.targetPath(a, ref, "calc.zig");
    try expectEqualStrings("test/fixtures/projects/arithmetic_kill/calc.zig", target);

    // Reuses the harness normalizer: absolute roots collapse to <project> and
    // backslashes become forward slashes so fixture paths stay deterministic.
    const norm = try fixture.normalizePath(
        a,
        "/abs/proj\\test\\fixtures\\projects\\arithmetic_kill\\calc.zig",
        "/abs/proj",
    );
    try expectEqualStrings("<project>/test/fixtures/projects/arithmetic_kill/calc.zig", norm);
}
