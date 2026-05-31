const std = @import("std");
const zentinel = @import("zentinel");
const normalizer = zentinel.doctest.normalizer;
const matcher = zentinel.doctest.matcher;
const snapshot = zentinel.doctest.snapshot;
const runner = zentinel.doctest.runner;
const case = zentinel.doctest.case;
const proc = zentinel.runner;
const error_codes = zentinel.error_codes;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn norm(a: std.mem.Allocator, text: []const u8, opts: normalizer.Options) ![]const u8 {
    return normalizer.normalize(a, text, opts);
}

// ----- normalizer -----

test "normalizer rewrites absolute project paths to <project>" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try norm(a, "error at /Users/x/proj/src/a.zig:1: bad", .{ .project_root = "/Users/x/proj" });
    try expectEqualStrings("error at <project>/src/a.zig:1: bad", out);
}

test "normalizer rewrites durations to <duration>" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectEqualStrings("ran in <duration>", try norm(a, "ran in 1234ms", .{}));
    try expectEqualStrings("took <duration> total", try norm(a, "took 1.5s total", .{}));
}

test "normalizer rewrites run ids to a stable placeholder" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectEqualStrings("doctest_run_<id> done", try norm(a, "doctest_run_01hr7pc9qdyj2f3d7z7me3x1rk done", .{}));
}

test "normalizer rewrites temp directories to <tmp>" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectEqualStrings("wrote <tmp>", try norm(a, "wrote /var/folders/ab/cd/T/zentinel123/out.json", .{}));
    try expectEqualStrings("at <tmp> ok", try norm(a, "at /tmp/zentinel/work ok", .{}));
}

test "property: normalization is idempotent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = "run doctest_run_01hr7p in /tmp/z/w took 12ms at /Users/x/proj/src/a.zig\r\nline two   \n";
    const n1 = try norm(a, raw, .{ .project_root = "/Users/x/proj" });
    const n2 = try norm(a, n1, .{ .project_root = "/Users/x/proj" });
    try expectEqualStrings(n1, n2);
}

test "property: text normalization preserves meaningful line order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try norm(a, "bravo\nalpha\ncharlie\n", .{});
    const b = std.mem.indexOf(u8, out, "bravo").?;
    const al = std.mem.indexOf(u8, out, "alpha").?;
    const c = std.mem.indexOf(u8, out, "charlie").?;
    try expect(b < al and al < c);
}

// ----- matcher -----

test "exact text matching" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try matcher.match(a, .exact, "a\nb\n", "a\nb\n"));
    try expect(!try matcher.match(a, .exact, "a\nb\n", "a\nc\n"));
}

test "contains text matching requires expected lines in order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try matcher.match(a, .contains, "needle", "hay\nneedle\nstack"));
    try expect(try matcher.match(a, .contains, "one\nthree", "one\ntwo\nthree"));
    try expect(!try matcher.match(a, .contains, "three\none", "one\ntwo\nthree"));
    try expect(!try matcher.match(a, .contains, "absent", "hay stack"));
}

test "regex text matching" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try matcher.match(a, .regex, "ran in [0-9]+ms", "ran in 123ms"));
    try expect(try matcher.match(a, .regex, "^zentinel.*testing$", "zentinel - mutation testing"));
    try expect(!try matcher.match(a, .regex, "^[0-9]+$", "12a"));
}

test "json exact matching is key-order independent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try matcher.match(a, .json, "{\"a\":1,\"b\":2}", "{\"b\":2,\"a\":1}"));
    try expect(!try matcher.match(a, .json, "{\"a\":1}", "{\"a\":2}"));
    try expect(!try matcher.match(a, .json, "{\"a\":1}", "{\"a\":1,\"b\":2}"));
}

test "json subset matching allows extra actual keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try matcher.match(a, .json_subset, "{\"summary\":{\"survived\":1}}", "{\"schema\":\"x\",\"summary\":{\"survived\":1,\"killed\":2}}"));
    try expect(!try matcher.match(a, .json_subset, "{\"missing\":1}", "{\"a\":1}"));
}

test "json unordered matching treats arrays as multisets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expect(try matcher.match(a, .json_unordered, "[1,2,3]", "[3,1,2]"));
    try expect(!try matcher.match(a, .json_unordered, "[1,2,3]", "[1,2,4]"));
    // Ordered json mode rejects a reordered array.
    try expect(!try matcher.match(a, .json, "[1,2,3]", "[3,1,2]"));
}

test "diagnostic matching normalizes line/col then matches by containment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Differing line/column numbers must not defeat a diagnostic match.
    try expect(try matcher.match(a, .diagnostic, "a.zig:5:9: error: expected type 'void'", "<project>/a.zig:7:3: error: expected type 'void'"));
    try expect(!try matcher.match(a, .diagnostic, "error: expected type 'void'", "error: expected type 'u32'"));
}

// ----- snapshot orchestration -----

test "snapshot mismatch yields a ZNTL_DOCTEST_SNAPSHOT_MISMATCH diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try snapshot.compare(a, "dt_x", "doc.md", 5, .exact, "expected text\n", "actual text\n", .{});
    try expect(!r.matched);
    try expect(r.diagnostic != null);
    try expectEqualStrings(error_codes.doctest_snapshot_mismatch, r.diagnostic.?.code);
    try expectEqualStrings("doc.md", r.diagnostic.?.file);
    try expectEqual(@as(u32, 5), r.diagnostic.?.line);
    try expectEqualStrings("dt_x", r.diagnostic.?.case_id);

    const rendered = try snapshot.renderDiagnostic(a, r);
    const want = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/fixtures/doctest/snapshots/mismatch.txt", a, std.Io.Limit.limited(1 << 20));
    try expectEqualStrings(want, rendered);
}

test "snapshot match passes with no diagnostic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r = try snapshot.compare(a, "dt_y", "doc.md", 9, .contains, "zentinel", "zentinel - mutation testing\n", .{});
    try expect(r.matched);
    try expect(r.diagnostic == null);
}

test "snapshot validates actual runner output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A cli case result whose stdout the doctest produced.
    const result = runner.CaseResult{
        .id = "dt_cli",
        .kind = .cli,
        .status = .passed,
        .command = "zentinel --help",
        .argv = null,
        .exit_code = 0,
        .timed_out = false,
        .stdout_excerpt = "zentinel - mutation testing\nUsage: zentinel <command>\n",
        .stderr_excerpt = "",
        .skip_reason = null,
        .diagnostics = &.{},
    };
    const r = try snapshot.matchResultOutput(a, result, "doc.md", 12, .contains, "zentinel - mutation testing", .{});
    try expect(r.matched);
    try expectEqualStrings("dt_cli", r.case_id);
}

test "property: json object key order does not affect json matching" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ordered = "{\"x\":{\"a\":1,\"b\":2},\"y\":3}";
    const shuffled = "{\"y\":3,\"x\":{\"b\":2,\"a\":1}}";
    try expect(try matcher.match(a, .json, ordered, shuffled));
}

test "property: snapshot mismatch output is deterministic across runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const r1 = try snapshot.compare(a, "dt_x", "doc.md", 5, .exact, "expected\n", "actual\n", .{});
    const r2 = try snapshot.compare(a, "dt_x", "doc.md", 5, .exact, "expected\n", "actual\n", .{});
    const d1 = try snapshot.renderDiagnostic(a, r1);
    const d2 = try snapshot.renderDiagnostic(a, r2);
    try expectEqualStrings(d1, d2);
}
