const std = @import("std");
const zentinel = @import("zentinel");

const report = zentinel.report;
const config = zentinel.config;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn readFile(a: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

/// The body of a top-level `fn <sig>` declaration: from the signature to the next
/// top-level `fn ` boundary (all targeted functions in src/cli.zig are private `fn`).
fn fnBody(src: []const u8, sig: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, src, sig) orelse return "";
    const after = start + sig.len;
    const end = std.mem.indexOf(u8, src[after..], "\nfn ") orelse (src.len - after);
    return src[start .. after + end];
}

// --- Repeated report comparison (F-025) ------------------------------------

test "initial production dogfood report is deterministic across repeated runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Two advisory dogfood runs over the same selected production modules differ
    // only in run id, timestamps, and durations; normalized they are identical,
    // so repeated dogfood output is deterministic.
    const run1 = try readFile(a, "test/fixtures/dogfood/production/run1.report.json");
    const run2 = try readFile(a, "test/fixtures/dogfood/production/run2.report.json");
    try expect(!std.mem.eql(u8, run1, run2)); // raw bytes differ (id/timestamps/durations)

    const n1 = try report.normalizeForComparison(a, run1);
    const n2 = try report.normalizeForComparison(a, run2);
    try expectEqualStrings(n1, n2);
}

test "production dogfood report selects only production scope and has no invalid mutants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = try readFile(a, "test/fixtures/dogfood/production/run1.report.json");
    const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    try expectEqualStrings("zentinel.report.v1", parsed.value.object.get("schema_version").?.string);
    const mutants = parsed.value.object.get("mutants").?.array.items;
    try expect(mutants.len > 0);
    for (mutants) |m| {
        // No invalid mutants appear in protected (production) scope.
        const status = m.object.get("result").?.object.get("status").?.string;
        try expect(!std.mem.eql(u8, status, "invalid"));
        // Only selected production-source modules are dogfooded.
        const file = m.object.get("file").?.string;
        try expect(std.mem.startsWith(u8, file, "src/"));
    }
}

// --- Production dogfood config ----------------------------------------------

test "production dogfood config selects production src modules deterministically" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bytes = try readFile(a, "test/fixtures/dogfood/production/config.toml");
    var diag: config.Diagnostic = .{};
    const cfg = try config.load(a, bytes, &diag);
    try expect(cfg.include.len > 0);
    try expect(std.mem.startsWith(u8, cfg.include[0], "src/"));
    try expect(cfg.test_commands.len >= 1);
    // Default Debug mode keeps the initial dogfood single-mode and deterministic.
    try expect(cfg.zig_modes.len == 1);
}

// --- Canonical CI entrypoint ------------------------------------------------

test "scripts/ci.sh is the canonical entrypoint running the required deterministic stages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ci = try readFile(a, "scripts/ci.sh");
    // The required deterministic verification stages, in the documented order.
    try expect(std.mem.indexOf(u8, ci, "zig fmt --check") != null);
    try expect(std.mem.indexOf(u8, ci, "zig build") != null);
    try expect(std.mem.indexOf(u8, ci, "zig build test") != null);
    // Advisory dogfood stage is wired.
    try expect(std.mem.indexOf(u8, ci, "dogfood") != null);
    // Network-independent: the deterministic entrypoint never requires a remote
    // AI provider.
    try expect(std.mem.indexOf(u8, ci, "remote_allowed = true") == null);
    // A --list mode enumerates the stages without running them.
    try expect(std.mem.indexOf(u8, ci, "--list") != null);
}

test "CLI_SPEC enumerates the external-Zig command grouping and it matches cli.zig" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Doc: CLI_SPEC now has the authoritative "External Zig binary requirement"
    // enumeration that names which commands need the external zig binary.
    const spec = try readFile(a, "docs/CLI_SPEC.md");
    try expect(std.mem.indexOf(u8, spec, "External Zig binary requirement") != null);
    try expect(std.mem.indexOf(u8, spec, "list-mutants") != null);
    // FAILURE_MODES F-001 no longer uses the vague "commands that require Zig" and
    // instead points at the CLI_SPEC grouping.
    const fm = try readFile(a, "docs/FAILURE_MODES.md");
    try expect(std.mem.indexOf(u8, fm, "External Zig binary requirement") != null);

    // Code ground truth the doc is describing: the external-zig fatal gate
    // (zig_version.fatalStatusLine) is called by `run` and `doctest` but NOT by
    // `list-mutants`, which uses only the embedded std.zig.Ast parser. If a future
    // edit moved the gate, this cross-check fails so the doc cannot silently drift.
    const cli = try readFile(a, "src/cli.zig");
    try expect(std.mem.indexOf(u8, fnBody(cli, "fn runRun("), "fatalStatusLine") != null);
    try expect(std.mem.indexOf(u8, fnBody(cli, "fn runDoctest("), "fatalStatusLine") != null);
    try expect(std.mem.indexOf(u8, fnBody(cli, "fn runListMutants("), "fatalStatusLine") == null);
}

test "build.zig fails loudly instead of silently skipping unit tests when test/ is inaccessible" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bz = try readFile(a, "build.zig");
    // A missing/unreadable test/ now panics (the silent `catch return` is gone) and
    // discovering zero test/**/*_test.zig files is a hard error, so `zig build test`
    // can no longer exit 0 having run none of the discovered unit tests.
    try expect(std.mem.indexOf(u8, bz, "zig build test cannot discover unit tests") != null);
    try expect(std.mem.indexOf(u8, bz, "no test/**/*_test.zig files discovered") != null);
}

test "advisory_dogfood surfaces dogfood stderr and blames infrastructure, not survivors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ci = try readFile(a, "scripts/ci.sh");

    // The advisory dogfood suppresses only the dogfood STDOUT; its STDERR passes
    // through so an infrastructure/deterministic-core failure's real cause is
    // visible in the CI log. The old `>/dev/null 2>&1` swallowed BOTH streams,
    // making the actual build/crash/runtime error unrecoverable from the log.
    try expect(std.mem.indexOf(u8, ci, "scripts/dogfood.sh >/dev/null") != null);
    try expect(std.mem.indexOf(u8, ci, "2>&1") == null);

    // dogfood.sh does not pass --fail-on-survivors, so survivors exit 0; a non-zero
    // status is therefore ALWAYS an infrastructure/deterministic-core error, never a
    // survivor. The advisory message must not misdirect developers to "review
    // survivors" -- it must name the real (infrastructure) failure mode.
    try expect(std.mem.indexOf(u8, ci, "review survivors") == null);
    try expect(std.mem.indexOf(u8, ci, "infrastructure") != null);
}
