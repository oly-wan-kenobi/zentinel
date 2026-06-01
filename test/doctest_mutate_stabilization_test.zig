const std = @import("std");
const zentinel = @import("zentinel");

const me = zentinel.doctest.mutation_experiment;
const mid = zentinel.doctest.mutation_id;
const runner = zentinel.runner;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

// A mutated snippet that becomes `return a - b` fails the doctest (exit 1);
// everything else passes. Drives killed/survived/preflight outcomes over the
// shared fixtures.
const Mock = struct {
    fn run(ctx: *anyopaque, mutated: []const u8) runner.RawOutcome {
        _ = ctx;
        const broke = std.mem.indexOf(u8, mutated, "return a - b") != null;
        return .{
            .exit_code = if (broke) 1 else 0,
            .timed_out = false,
            .crashed = false,
            .duration_ms = 0,
            .stdout = "",
            .stderr = if (broke) "doctest assertion failed" else "",
        };
    }
};
fn mock() me.SnippetRunner {
    return .{ .ctx = undefined, .runFn = Mock.run };
}
fn readFile(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, std.Io.Limit.limited(1 << 20));
}

const base = "test/fixtures/doctest/mutation/";
const killed_snapshot = @embedFile("fixtures/doctest/mutation_stabilization/killed.stable.json");
const survived_snapshot = @embedFile("fixtures/doctest/mutation_stabilization/survived.stable.json");

// --- Opt-in gating ---------------------------------------------------------

test "doctest --mutate stabilization rejects non-opt-in documentation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readFile(a, base ++ "killed.md");
    try expectError(error.NotOptedIn, me.stableMutationRun(a, "docs/killed.md", src, mock(), false));
}

test "stable mutation report records invalid snippets instead of dropping candidates silently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const invalid_src =
        \\# invalid snippet
        \\
        \\```zig test
        \\const std = @import("std");
        \\
        \\test "invalid but asserted" {
        \\    try std.testing.expect(true)
        \\}
        \\```
        \\
    ;
    const r = try me.stableMutationRun(a, "docs/invalid.md", invalid_src, mock(), true);
    try expectEqual(@as(u64, 1), r.summary.mutation.total);
    try expectEqual(@as(u64, 1), r.summary.mutation.invalid);
    try expectEqual(@as(usize, 1), r.cases.len);
    try expectEqualStrings("invalid", r.cases[0].status);
    try expectEqualStrings("backend: could not parse doctest mutation snippet", r.cases[0].mutation.runner_evidence.failure_summary);
    try expect(r.cases[0].mutation.survivor_ref == null);
}

test "doctest --mutate JSON uses the public doctest.report.v1 shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readFile(a, base ++ "killed.md");

    const json = try me.mutateReportJson(a, "docs/killed.md", src, mock());
    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    const obj = parsed.value.object;

    try expectEqualStrings("zentinel.doctest.report.v1", obj.get("schema_version").?.string);
    try expect(obj.get("run") != null);
    try expect(obj.get("summary") != null);
    try expect(obj.get("mutation_summary") == null);
    try expect(obj.get("summary").?.object.get("mutation") != null);

    const first = obj.get("cases").?.array.items[0].object;
    try expectEqualStrings("mutation", first.get("kind").?.string);
    try expect(first.get("expectation") != null);
    try expect(first.get("command") != null);
    try expect(first.get("result") != null);
    try expect(first.get("diagnostics") != null);
    try expect(first.get("advisory") != null);

    const mutation = first.get("mutation").?.object;
    try expectEqualStrings("stable", mutation.get("operator_stability").?.string);
    try expectEqualStrings("ast", mutation.get("backend").?.string);
    try expectEqualStrings("stable", mutation.get("backend_stability").?.string);
    try expectEqualStrings("docs/killed.md", mutation.get("doc_file").?.string);
    try expect(mutation.get("doc_line").?.integer > 0);
    try expectEqualStrings(first.get("source_ref").?.string, mutation.get("source_ref").?.string);
}

// --- Deterministic stable mutation report snapshots ------------------------

test "deterministic stable mutation report snapshot for killed/survived mutants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readFile(a, base ++ "killed.md");
    const r = try me.stableMutationRun(a, "docs/killed.md", src, mock(), true);
    try expect(r.cases.len > 0);
    try expect(r.summary.mutation.killed >= 1);
    const json = try me.stableToJson(a, r);
    try expectEqualStrings(std.mem.trimEnd(u8, killed_snapshot, "\n"), json);
}

test "survived documentation mutant gets a ds_ survivor ref and a stable snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readFile(a, base ++ "survived.md");
    const r = try me.stableMutationRun(a, "docs/survived.md", src, mock(), true);
    var found = false;
    for (r.cases) |c| {
        if (std.mem.eql(u8, c.status, "survived")) {
            const ref = c.mutation.survivor_ref orelse return error.TestUnexpectedResult;
            try expect(std.mem.startsWith(u8, ref, "ds_"));
            try expect(std.mem.startsWith(u8, c.id, "dm_"));
            found = true;
        }
    }
    try expect(found);
    const json = try me.stableToJson(a, r);
    try expectEqualStrings(std.mem.trimEnd(u8, survived_snapshot, "\n"), json);
}

// --- runner_evidence carries failure_kind ----------------------------------

test "mutation-aware runner evidence includes failure_kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readFile(a, base ++ "killed.md");
    const r = try me.stableMutationRun(a, "docs/killed.md", src, mock(), true);
    for (r.cases) |c| {
        try expect(c.mutation.runner_evidence.failure_kind.len > 0);
        try expectEqualStrings("mutation", c.kind);
    }
}

// --- Repeatability + survivor-ref discipline -------------------------------

test "identical inputs produce identical survivor refs; non-survived have none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const survived_src = try readFile(a, base ++ "survived.md");
    const r1 = try me.stableMutationRun(a, "docs/survived.md", survived_src, mock(), true);
    const r2 = try me.stableMutationRun(a, "docs/survived.md", survived_src, mock(), true);
    try expectEqual(r1.cases.len, r2.cases.len);
    for (r1.cases, r2.cases) |c1, c2| {
        try expectEqualStrings(c1.id, c2.id); // dm_ id repeatable
        if (c1.mutation.survivor_ref) |ref1| {
            try expectEqualStrings(ref1, c2.mutation.survivor_ref.?); // ds_ repeatable
        } else {
            try expect(c2.mutation.survivor_ref == null);
        }
    }

    // Killed and skipped documentation mutants never receive survivor refs.
    const killed_src = try readFile(a, base ++ "killed.md");
    const rk = try me.stableMutationRun(a, "docs/killed.md", killed_src, mock(), true);
    for (rk.cases) |c| {
        if (!std.mem.eql(u8, c.status, "survived")) {
            try expect(c.mutation.survivor_ref == null);
        }
    }
}

// --- Normal doctest failure blocks mutation-aware execution ----------------

test "normal doctest failure blocks mutation-aware execution for that case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try readFile(a, base ++ "preflight_fail.md");
    const r = try me.stableMutationRun(a, "docs/preflight_fail.md", src, mock(), true);
    try expect(r.cases.len >= 1);
    for (r.cases) |c| {
        try expectEqualStrings("skipped", c.status);
        try expectEqual(@as(usize, 0), c.mutation.mutant_id.len); // no mutant executed
        try expectEqualStrings("normal_doctest_did_not_pass", c.mutation.runner_evidence.skip_reason.?);
    }
    try expect(r.summary.mutation.skipped >= 1);
    try expectEqual(@as(u64, 0), r.summary.mutation.killed);
    try expectEqual(@as(u64, 0), r.summary.mutation.survived);
}

// --- Schema agreement + identity determinism -------------------------------

test "doctest.report.v1 schema defines the additive mutation extension" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema_src = try readFile(a, "schemas/doctest.report.v1.schema.json");
    const parsed = try std.json.parseFromSlice(std.json.Value, a, schema_src, .{});
    const defs = parsed.value.object.get("$defs").?.object;
    try expect(defs.get("case_mutation") != null);
    try expect(defs.get("mutation_runner_evidence") != null);
    try expect(defs.get("mutation_summary") != null);

    // case carries an optional mutation property; summary carries summary.mutation.
    const case_props = defs.get("case").?.object.get("properties").?.object;
    try expect(case_props.get("mutation") != null);
    const summary_props = defs.get("summary").?.object.get("properties").?.object;
    try expect(summary_props.get("mutation") != null);

    // The case status enum was widened to include mutation statuses.
    const status_enum = case_props.get("status").?.object.get("enum").?.array.items;
    var has_killed = false;
    var has_survived = false;
    for (status_enum) |s| {
        if (std.mem.eql(u8, s.string, "killed")) has_killed = true;
        if (std.mem.eql(u8, s.string, "survived")) has_survived = true;
    }
    try expect(has_killed and has_survived);

    // runner_evidence requires failure_kind.
    const ev_required = defs.get("mutation_runner_evidence").?.object.get("required").?.array.items;
    var has_failure_kind = false;
    for (ev_required) |r| {
        if (std.mem.eql(u8, r.string, "failure_kind")) has_failure_kind = true;
    }
    try expect(has_failure_kind);

    const ev_props = defs.get("mutation_runner_evidence").?.object.get("properties").?.object;
    const runner_status_enum = ev_props.get("status").?.object.get("enum").?.array.items;
    var has_runner_killed = false;
    var has_runner_survived = false;
    for (runner_status_enum) |value| {
        if (std.mem.eql(u8, value.string, "killed")) has_runner_killed = true;
        if (std.mem.eql(u8, value.string, "survived")) has_runner_survived = true;
    }
    try expect(has_runner_killed and has_runner_survived);

    const failure_kind_enum = ev_props.get("failure_kind").?.object.get("enum").?.array.items;
    var has_invalid_failure_kind = false;
    for (failure_kind_enum) |value| {
        if (std.mem.eql(u8, value.string, "invalid")) has_invalid_failure_kind = true;
    }
    try expect(has_invalid_failure_kind);

    const mutation_required = defs.get("case_mutation").?.object.get("required").?.array.items;
    for ([_][]const u8{ "operator_stability", "backend", "backend_stability", "doc_file", "doc_line", "source_ref" }) |required_field| {
        var found = false;
        for (mutation_required) |r| {
            if (std.mem.eql(u8, r.string, required_field)) found = true;
        }
        try expect(found);
    }

    const case_rules = defs.get("case").?.object.get("allOf").?.array.items;
    var has_survivor_rule = false;
    for (case_rules) |rule| {
        const txt = try std.json.Stringify.valueAlloc(a, rule, .{});
        if (std.mem.indexOf(u8, txt, "survivor_ref") != null and std.mem.indexOf(u8, txt, "survived") != null) {
            has_survivor_rule = true;
        }
    }
    try expect(has_survivor_rule);
}

test "dm_ and ds_ derivation is deterministic and distinct" {
    const ident = mid.Identity{
        .doctest_case_id = "dt_0000000000000000000000000a",
        .mutant_id = "m_0000000000000000000000000b",
        .operator = "comparison_boundary",
        .doc_file = "docs/x.md",
        .source_ref = "docs/x.md:3",
        .normalized_mutated_diff = "- a >= 0\n+ a > 0",
    };
    const dm1 = mid.mutationCaseId(ident);
    const dm2 = mid.mutationCaseId(ident);
    try expectEqualStrings(&dm1, &dm2); // deterministic
    try expect(std.mem.startsWith(u8, &dm1, "dm_"));
    try expectEqual(@as(usize, mid.id_len), dm1.len);

    const ds1 = mid.survivorRef(ident);
    try expect(std.mem.startsWith(u8, &ds1, "ds_"));
    // dm_ and ds_ use distinct namespaces, so their 26-char bodies differ.
    try expect(!std.mem.eql(u8, dm1[3..], ds1[3..]));
}
