const std = @import("std");
const zentinel = @import("zentinel");

const rc = zentinel.run_command;
const runner = zentinel.runner;
const report = zentinel.report;
const mutant_runner = zentinel.mutant_runner;
const mutant = zentinel.mutant;
const config = zentinel.config;

const expectEqualStrings = std.testing.expectEqualStrings;
const expect = std.testing.expect;

// One arithmetic_add_sub mutant, no same-file tests (so selection does not narrow).
const add_src = "pub fn add(a: i32, b: i32) i32 {\n    return a + b;\n}\n";

const cfg_toml =
    \\[project]
    \\name = "det"
    \\
    \\[mutators]
    \\enabled = ["arithmetic_add_sub"]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\
;

// The mutant is killed; its stderr is a panic-style stack trace carrying an ASLR
// pointer address and an absolute machine path -- the two pieces that differ
// between real runs (and across machines) but must not make reports differ.
const RunEnv = struct { arena: std.mem.Allocator, stderr: []const u8, duration: u64 };

fn baselineCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = ctx;
    _ = argv;
    return .{ .exit_code = 0, .timed_out = false, .crashed = false, .duration_ms = 1, .stdout = "", .stderr = "" };
}
fn mutantCmd(ctx: *anyopaque, argv: []const []const u8) runner.RawOutcome {
    _ = argv;
    const env: *RunEnv = @ptrCast(@alignCast(ctx));
    return .{ .exit_code = 1, .timed_out = false, .crashed = false, .duration_ms = env.duration, .stdout = "", .stderr = env.stderr };
}
fn mutantRunFn(ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
    const env: *RunEnv = @ptrCast(@alignCast(ctx));
    const ex = runner.Executor{ .ctx = env, .runFn = mutantCmd };
    return mutant_runner.run(env.arena, m, source, .created, commands, "<project>", ex, mode) catch @panic("mutant run failed");
}

fn buildReport(a: std.mem.Allocator, env: *RunEnv, observation: rc.Observation) !report.Report {
    var diag: config.Diagnostic = .{};
    const cfg = try config.load(a, cfg_toml, &diag);
    const files = [_]rc.FileSource{.{ .path = "src/add.zig", .source = add_src }};
    const baseline_executor = runner.Executor{ .ctx = env, .runFn = baselineCmd };
    const mutant_executor = rc.MutantRunner{ .ctx = env, .runFn = mutantRunFn };
    const outcome = try rc.run(a, cfg, &files, .{}, baseline_executor, mutant_executor, observation);
    return outcome.report;
}

fn obs(run_id: []const u8, started_at: []const u8, duration: u64) rc.Observation {
    return .{ .run_id = run_id, .started_at = started_at, .project_root = "<project>", .zentinel_version = "0.0.0", .zig_version = "0.16.0", .config_hash = "sha256:0", .duration_ms = duration };
}

test "repeated runs whose excerpts differ only in addresses and absolute paths normalize equal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two real runs of the same project on different machines / process layouts:
    // the killed mutant's stderr carries a different ASLR address and a different
    // absolute source path, plus different run id / timestamp / durations.
    // The two stderr strings differ ONLY in an ASLR pointer address and an
    // absolute source path (the two pieces task 108 normalizes); everything else
    // is identical, matching the audit repro.
    var env1 = RunEnv{
        .arena = a,
        .stderr = "thread 1 panic: reached unreachable code\n/home/alice/proj/src/add.zig:2:5: 0xaaaa1111 in add (test)\n    return a + b;\n",
        .duration = 7,
    };
    var env2 = RunEnv{
        .arena = a,
        .stderr = "thread 1 panic: reached unreachable code\n/Users/bob/checkout/src/add.zig:2:5: 0xbbbbbbbb2222 in add (test)\n    return a + b;\n",
        .duration = 113,
    };

    const r1 = try buildReport(a, &env1, obs("run_aaaaaaaaaaaaaaaaaaaa", "1970-01-01T00:00:00Z", 5));
    const r2 = try buildReport(a, &env2, obs("run_bbbbbbbbbbbbbbbbbbbb", "2026-05-31T12:34:56Z", 99));

    // Both runs killed the mutant; sanity-check the evidence is actually present
    // so the comparison is meaningful (not equal because excerpts are empty).
    try expect(r1.mutants.len == 1);
    try expect(r1.mutants[0].result.status == .killed);
    try expect(r1.mutants[0].result.commands.len >= 1);
    try expect(r1.mutants[0].result.commands[0].evidence.stderr_excerpt.len > 0);

    const n1 = try report.normalizeForComparison(a, try report.toJson(a, r1));
    const n2 = try report.normalizeForComparison(a, try report.toJson(a, r2));
    try expectEqualStrings(n1, n2);
}

test "normalizeExcerpt replaces hex addresses and absolute paths but keeps other text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const raw = "panic at /Users/oli/zentinel/src/x.zig:7:3: 0xdeadBEEF in f (line a + b)";
    const norm = try report.normalizeExcerpt(a, raw);
    // The address and the absolute path are gone; the surrounding prose stays.
    try expect(std.mem.indexOf(u8, norm, "0xdeadBEEF") == null);
    try expect(std.mem.indexOf(u8, norm, "/Users/oli") == null);
    try expect(std.mem.indexOf(u8, norm, "0x<addr>") != null);
    try expect(std.mem.indexOf(u8, norm, "<path>") != null);
    try expect(std.mem.indexOf(u8, norm, "panic at ") != null);
    try expect(std.mem.indexOf(u8, norm, "in f (line a + b)") != null);

    // Two excerpts differing only in the address and the absolute path normalize
    // to identical bytes.
    const other = try report.normalizeExcerpt(a, "panic at /home/ci/build/src/x.zig:7:3: 0x12 in f (line a + b)");
    try expectEqualStrings(norm, other);

    const spaced = try report.normalizeExcerpt(a, "panic at \"/Users/oli/My Project/src/x.zig:7:3\"");
    try expectEqualStrings("panic at \"<path>\"", spaced);
    const unquoted_spaced = try report.normalizeExcerpt(a, "panic at /Users/oli/My Project/src/x.zig:7:3");
    try expectEqualStrings("panic at <path>", unquoted_spaced);
    const windows = try report.normalizeExcerpt(a, "panic at C:\\Users\\oli\\My Project\\src\\x.zig:7:3");
    try expectEqualStrings("panic at <path>", windows);
}

test "normalizeExcerpt preserves Zig // and /// comment markers in stderr excerpts (M3)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A `//`-led run is a Zig comment marker, not an absolute path. Committed
    // report excerpts that quote source lines must keep the comment intact rather
    // than collapsing it to `<path>` (M3).
    try expectEqualStrings("// boundary off-by-one", try report.normalizeExcerpt(a, "// boundary off-by-one"));
    try expectEqualStrings("/// doc comment", try report.normalizeExcerpt(a, "/// doc comment"));

    // A real absolute path on the same line is still redacted; the comment stays.
    try expectEqualStrings(
        "keep // and <path>",
        try report.normalizeExcerpt(a, "keep // and /home/ci/build/key"),
    );
}
