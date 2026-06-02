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
    try expect(std.mem.indexOf(u8, ci, "scripts/validate_task_system.py") != null);
    // Advisory dogfood stage is wired.
    try expect(std.mem.indexOf(u8, ci, "dogfood") != null);
    // Network-independent: the deterministic entrypoint never requires a remote
    // AI provider.
    try expect(std.mem.indexOf(u8, ci, "remote_allowed = true") == null);
    // A --list mode enumerates the stages without running them.
    try expect(std.mem.indexOf(u8, ci, "--list") != null);
}

test "validate_task_system resolve_zig_import resolves .zig imports relative to the importer (L48)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const vts = try readFile(a, "scripts/validate_task_system.py");
    // A Zig @import for a .zig file is always relative to the importing file's
    // directory; no src/**/*.zig uses @import("src/..."), so the project-root-relative
    // `src/` special case was dead. It is removed, leaving one resolution path (L48).
    try expect(std.mem.indexOf(u8, vts, "imported.startswith(\"src/\")") == null);
    try expect(std.mem.indexOf(u8, vts, "importer.parent / imported") != null);
}

test "validate_task_system requires allowed_files/forbidden_files to be non-empty, not vacuously-true (S13)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const vts = try readFile(a, "scripts/validate_task_system.py");
    // `all()` is vacuously True on [], so the "non-empty string array" guard for
    // allowed_files/forbidden_files silently accepted `[]` -- granting the task an
    // unconstrained scope (the scope checks only fire when the lists are non-empty).
    // The guard now requires a positive length before the all() check (S13). Verified
    // out-of-band: the predicate returns False for [] (was True) and is unchanged for
    // ["x"], [""], ["a","b"].
    try expect(std.mem.indexOf(u8, vts, "len(value) > 0 and all(isinstance(item, str)") != null);
}

test "validate_task_system requires completion_evidence files_changed to be non-empty (S14)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const vts = try readFile(a, "scripts/validate_task_system.py");
    // files_changed is the scope-critical completion-evidence field:
    // validate_completion_scope_evidence iterates it, so an empty list -- accepted by
    // the vacuous all() check -- silently bypasses the scope audit. A dedicated
    // non-empty guard now closes that hole (S14). Verified out-of-band: perturbing a
    // real status.json entry to files_changed=[] raises "files_changed must be a
    // non-empty string array"; the real data does not.
    try expect(std.mem.indexOf(u8, vts, "len(entry.get(\"files_changed\", [])) > 0") != null);
    try expect(std.mem.indexOf(u8, vts, "files_changed must be a non-empty string array") != null);
}

test "validate_failure_recovery flags a non-dict invalid fixture instead of skipping it (L49)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const vts = try readFile(a, "scripts/validate_task_system.py");
    // The invalid-fixture self-test loop now fail()s on a non-dict file (a
    // fixture-authoring error), mirroring the valid loop, instead of a silent
    // `continue` that hid the bad fixture (L49). This message exists only for the
    // invalid loop; the valid loop's says "valid ...".
    try expect(std.mem.indexOf(u8, vts, "invalid failure-recovery fixture must be a JSON object") != null);
}

test "build.zig fails loudly instead of silently skipping unit tests when test/ is inaccessible (S4)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bz = try readFile(a, "build.zig");
    // A missing/unreadable test/ now panics (the silent `catch return` is gone) and
    // discovering zero test/**/*_test.zig files is a hard error, so `zig build test`
    // can no longer exit 0 having run none of the discovered unit tests (S4).
    try expect(std.mem.indexOf(u8, bz, "zig build test cannot discover unit tests") != null);
    try expect(std.mem.indexOf(u8, bz, "no test/**/*_test.zig files discovered") != null);
}

test "advisory_dogfood surfaces dogfood stderr and blames infrastructure, not survivors (L33)" {
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
