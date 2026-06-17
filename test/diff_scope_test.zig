const std = @import("std");
const zentinel = @import("zentinel");

const config = zentinel.config;
const rc = zentinel.run_command;
const report = zentinel.report;
const runner = zentinel.runner;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

// --- Deterministic harness (mock executors), mirroring dogfood_fixture_test ---

const Env = struct {
    arena: std.mem.Allocator,
    baseline_outcome: runner.RawOutcome,
    mutant_outcome: runner.RawOutcome,
};

fn ok() runner.RawOutcome {
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
}
fn fail() runner.RawOutcome {
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "fail" };
}

fn baselineCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    return @as(*Env, @ptrCast(@alignCast(ctx))).baseline_outcome;
}
fn mutantCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    return @as(*Env, @ptrCast(@alignCast(ctx))).mutant_outcome;
}
fn mutantRunFn(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *Env = @ptrCast(@alignCast(ctx));
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, "<project>", ex, mode) catch @panic("mutant run failed");
}

fn observation(run_id: []const u8, started_at: []const u8, duration_ms: u64) rc.Observation {
    return .{
        .run_id = run_id,
        .started_at = started_at,
        .project_root = "<project>",
        .zentinel_version = "0.0.0",
        .zig_version = "0.16.0",
        .config_hash = "sha256:diff-scope",
        .zig_cache_namespace = ".zig-cache/zentinel/workspaces",
        .duration_ms = duration_ms,
    };
}

// Two source files, each yielding >=1 Phase 1 candidate under the enabled
// operators, so scoping to one of them is observable.
const a_src = "pub fn add(x: i32, y: i32) i32 {\n    return x + y;\n}\n";
const b_src = "pub fn lt(x: i32) bool {\n    return x < 10;\n}\n";

const cfg_toml =
    \\[project]
    \\name = "diff-scope"
    \\include = ["src/**/*.zig"]
    \\[mutators]
    \\enabled = ["arithmetic_add_sub", "comparison_boundary"]
    \\[test]
    \\commands = ["zig build test"]
;

fn loadCfg(a: std.mem.Allocator) !config.Config {
    var diag: config.Diagnostic = .{};
    return config.load(a, cfg_toml, &diag);
}

fn twoFiles() [2]rc.FileSource {
    return .{
        .{ .path = "src/a.zig", .source = a_src },
        .{ .path = "src/b.zig", .source = b_src },
    };
}

fn newEnv(a: std.mem.Allocator) Env {
    return .{ .arena = a, .baseline_outcome = ok(), .mutant_outcome = fail() };
}

fn executors(env: *Env) struct { baseline: runner.Executor, mutant: rc.MutantRunner } {
    return .{
        .baseline = runner.Executor{ .ctx = env, .runFn = baselineCmd },
        .mutant = rc.MutantRunner{ .ctx = env, .runFn = mutantRunFn },
    };
}

test "diff-scope over ALL files reproduces the unscoped report byte-for-byte" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cfg = try loadCfg(a);
    const files = twoFiles();
    var env = newEnv(a);
    const ex = executors(&env);
    const obs = observation("run_aaaaaaaa", "2026-01-01T00:00:00Z", 5);

    // Scoping to the FULL discovered set must be a no-op: identical inputs and
    // observation metadata, so the report is byte-identical to the unscoped run.
    const full = try rc.run(a, cfg, &files, .{}, ex.baseline, ex.mutant, obs);
    const scoped_all = try rc.run(a, cfg, &files, .{ .scope_files = &.{ "src/a.zig", "src/b.zig" } }, ex.baseline, ex.mutant, obs);

    try expect(full.report.mutants.len > 0);
    const norm_full = try report.normalizeForComparison(a, try report.toJson(a, full.report));
    const norm_all = try report.normalizeForComparison(a, try report.toJson(a, scoped_all.report));
    try expectEqualStrings(norm_full, norm_all);
}

test "diff-scope is deterministic across observation metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cfg = try loadCfg(a);
    const files = twoFiles();
    var env = newEnv(a);
    const ex = executors(&env);

    // Same scope, runs that differ ONLY in observation metadata -> after
    // normalization the reports must be byte-identical (the mode is deterministic).
    const scope: []const []const u8 = &.{"src/a.zig"};
    const run1 = try rc.run(a, cfg, &files, .{ .scope_files = scope }, ex.baseline, ex.mutant, observation("run_aaaaaaaa", "2026-01-01T00:00:00Z", 5));
    const run2 = try rc.run(a, cfg, &files, .{ .scope_files = scope }, ex.baseline, ex.mutant, observation("run_bbbbbbbb", "2026-02-02T02:02:02Z", 99));

    const norm1 = try report.normalizeForComparison(a, try report.toJson(a, run1.report));
    const norm2 = try report.normalizeForComparison(a, try report.toJson(a, run2.report));
    try expectEqualStrings(norm1, norm2);
}

test "diff-scope yields exactly the full run's mutants for the scoped files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const cfg = try loadCfg(a);
    const files = twoFiles();
    var env = newEnv(a);
    const ex = executors(&env);
    const obs = observation("run_aaaaaaaa", "2026-01-01T00:00:00Z", 5);

    const full = try rc.run(a, cfg, &files, .{}, ex.baseline, ex.mutant, obs);
    const scoped = try rc.run(a, cfg, &files, .{ .scope_files = &.{"src/a.zig"} }, ex.baseline, ex.mutant, obs);

    // Count the full run's mutants that belong to the scoped file.
    var expected_a: usize = 0;
    for (full.report.mutants) |m| {
        if (std.mem.eql(u8, m.file, "src/a.zig")) expected_a += 1;
    }
    try expect(expected_a > 0); // the fixture must actually exercise scoping
    try expect(full.report.mutants.len > expected_a); // and b.zig must contribute too
    try expectEqual(expected_a, scoped.report.mutants.len);

    // Every scoped mutant is on the scoped file and matches the full run's verdict
    // for the SAME durable id (scoping omits-only; it never alters a verdict).
    for (scoped.report.mutants) |sm| {
        try expectEqualStrings("src/a.zig", sm.file);
        var matched = false;
        for (full.report.mutants) |fm| {
            if (std.mem.eql(u8, fm.id, sm.id)) {
                try expectEqual(fm.result.status, sm.result.status);
                try expectEqualStrings(fm.file, sm.file);
                matched = true;
                break;
            }
        }
        try expect(matched);
    }
}

test "parseArgs accepts diff-scope flags and rejects combining them" {
    // --changed-only / --diff <ref> / --scope-files <csv> parse into raw inputs.
    const changed = try rc.parseArgs(&.{"--changed-only"});
    try expect(changed.changed_only);

    const diff = try rc.parseArgs(&.{ "--diff", "main" });
    try expectEqualStrings("main", diff.diff_base.?);

    const scoped = try rc.parseArgs(&.{ "--scope-files", "src/a.zig,src/b.zig" });
    try expectEqualStrings("src/a.zig,src/b.zig", scoped.scope_files_csv.?);

    // Mutually exclusive: combining any two scope inputs is a usage error.
    try std.testing.expectError(error.ConflictingOptions, rc.parseArgs(&.{ "--changed-only", "--diff", "main" }));
    try std.testing.expectError(error.ConflictingOptions, rc.parseArgs(&.{ "--changed-only", "--scope-files", "x.zig" }));
    try std.testing.expectError(error.MissingValue, rc.parseArgs(&.{"--scope-files"}));
}
