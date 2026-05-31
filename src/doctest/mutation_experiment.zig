// Layer: deterministic_core
//
// EXPERIMENTAL `zentinel doctest --mutate` prototype (docs/DOCTEST_MUTATION_STRATEGY.md).
// It mutates an executable `zig test` doctest snippet with the stable Phase 1 AST
// operators and classifies each documentation mutant as killed/survived through
// the SHARED mutant model and result classification (mutant_runner). A normal
// doctest must pass first (preflight); examples without a behavioral assertion
// are skipped with a deterministic reason. Execution of mutated snippets is
// injected (the CLI writes a generated workspace and runs `zig test`; tests
// inject a mock), so the documentation file is never modified. Not stabilized:
// the stable mutation-aware doctest report is owned by a later task.
const std = @import("std");
const ast_backend = @import("../ast_backend.zig");
const mutant = @import("../mutant.zig");
const arithmetic = @import("../mutators/arithmetic.zig");
const comparison = @import("../mutators/comparison.zig");
const logical = @import("../mutators/logical.zig");
const boolean = @import("../mutators/boolean.zig");
const runner = @import("../runner.zig");
const mutant_runner = @import("../mutant_runner.zig");
const report = @import("../report.zig");
const block = @import("block.zig");
const parser = @import("parser.zig");
const extractor = @import("extractor.zig");
const case_mod = @import("case.zig");

pub const schema_version = "zentinel.doctest.mutation_experiment.v1";

const snippet_file = "doctest_snippet.zig";
const mutate_command = "zig test src/doctest.zig";

/// Injected runner for a mutated doctest snippet. The real runner writes the
/// snippet into a generated workspace and runs `zig test`; tests inject a mock.
pub const SnippetRunner = struct {
    ctx: *anyopaque,
    runFn: *const fn (ctx: *anyopaque, mutated_source: []const u8) runner.RawOutcome,

    pub fn run(self: SnippetRunner, mutated_source: []const u8) runner.RawOutcome {
        return self.runFn(self.ctx, mutated_source);
    }
};

pub const RunnerEvidence = struct {
    status: []const u8,
    failure_kind: report.FailureKind,
    exit_code: ?i64,
    timed_out: bool,
    stdout_excerpt: []const u8,
    stderr_excerpt: []const u8,
};

pub const MutantOutcome = struct {
    mutant_id: []const u8,
    operator: []const u8,
    status: report.ResultStatus,
    /// Durable survivor ref (the surviving mutant id) when `status == survived`.
    survivor_ref: ?[]const u8,
    runner_evidence: RunnerEvidence,
};

pub const CaseExperiment = struct {
    doctest_case_id: []const u8,
    file: []const u8,
    line: u32,
    skipped: bool,
    skip_reason: ?[]const u8,
    mutants: []const MutantOutcome,
};

pub const Summary = struct {
    cases: u64 = 0,
    skipped_cases: u64 = 0,
    mutants: u64 = 0,
    killed: u64 = 0,
    survived: u64 = 0,
    other: u64 = 0,
};

pub const Report = struct {
    schema_version: []const u8 = schema_version,
    experimental: bool = true,
    summary: Summary,
    cases: []const CaseExperiment,
};

pub fn toJson(arena: std.mem.Allocator, r: Report) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, r, .{ .whitespace = .indent_2 });
}

/// Run the experimental mutation pass over a fixture doc. Only `zig test`
/// doctests are eligible; ordering follows the extractor's canonical case order.
pub fn run(arena: std.mem.Allocator, file: []const u8, source: []const u8, snippet_runner: SnippetRunner) std.mem.Allocator.Error!Report {
    const parsed = try parser.parse(arena, file, source);
    const extracted = try extractor.extract(arena, file, parsed.blocks, parsed.diagnostics);

    var cases: std.ArrayList(CaseExperiment) = .empty;
    var summary = Summary{};

    for (extracted.cases) |c| {
        if (c.kind != .zig_test) continue;
        const producer = findBlockByLine(parsed.blocks, c.anchor_line) orelse continue;
        const snippet = producer.content;
        summary.cases += 1;

        if (!hasBehavioralAssertion(snippet)) {
            summary.skipped_cases += 1;
            try cases.append(arena, skippedCase(c, "no_behavioral_assertion"));
            continue;
        }

        // Preflight: a normal doctest failure prevents mutation for this case.
        const pre = try classify(arena, snippet_runner.run(snippet));
        if (pre.status != .passed) {
            summary.skipped_cases += 1;
            try cases.append(arena, skippedCase(c, "normal_doctest_did_not_pass"));
            continue;
        }

        const cands = try candidates(arena, snippet);
        var outcomes: std.ArrayList(MutantOutcome) = .empty;
        for (cands) |m| {
            const mutated = try applyCandidate(arena, snippet, m);
            const cr = try classify(arena, snippet_runner.run(mutated));
            const single = try arena.dupe(report.CommandResult, &.{cr});
            const mr = mutant_runner.classifyFromCommands(m.id, .Debug, single);
            summary.mutants += 1;
            switch (mr.status) {
                .killed => summary.killed += 1,
                .survived => summary.survived += 1,
                else => summary.other += 1,
            }
            try outcomes.append(arena, .{
                .mutant_id = m.id,
                .operator = m.operator,
                .status = mr.status,
                .survivor_ref = if (mr.status == .survived) m.id else null,
                .runner_evidence = .{
                    .status = @tagName(mr.status),
                    .failure_kind = cr.failure_kind,
                    .exit_code = cr.exit_code,
                    .timed_out = cr.timed_out,
                    .stdout_excerpt = cr.evidence.stdout_excerpt,
                    .stderr_excerpt = cr.evidence.stderr_excerpt,
                },
            });
        }
        try cases.append(arena, .{
            .doctest_case_id = c.id,
            .file = c.file,
            .line = c.anchor_line,
            .skipped = false,
            .skip_reason = null,
            .mutants = try outcomes.toOwnedSlice(arena),
        });
    }

    return .{ .summary = summary, .cases = try cases.toOwnedSlice(arena) };
}

fn skippedCase(c: case_mod.Case, reason: []const u8) CaseExperiment {
    return .{
        .doctest_case_id = c.id,
        .file = c.file,
        .line = c.anchor_line,
        .skipped = true,
        .skip_reason = reason,
        .mutants = &.{},
    };
}

fn classify(arena: std.mem.Allocator, raw: runner.RawOutcome) std.mem.Allocator.Error!report.CommandResult {
    return runner.classifyCommand(arena, .mutant, mutate_command, &.{ "zig", "test", "src/doctest.zig" }, ".", raw);
}

/// A doctest has a behavioral assertion when it declares a `test` and uses an
/// `expect`/`try`-based check; otherwise it cannot kill any mutant.
fn hasBehavioralAssertion(snippet: []const u8) bool {
    return std.mem.indexOf(u8, snippet, "test") != null and std.mem.indexOf(u8, snippet, "expect") != null;
}

fn candidates(arena: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]mutant.Mutant {
    var parsed = ast_backend.parse(arena, snippet_file, source) catch return &.{};
    if (!parsed.ok()) return &.{};
    var collector = ast_backend.Collector.init(arena);
    const test_ranges = try ast_backend.testDeclRanges(parsed, arena);
    try arithmetic.collect(&collector, parsed, snippet_file, test_ranges);
    try comparison.collect(&collector, parsed, snippet_file, test_ranges);
    try logical.collect(&collector, parsed, snippet_file, test_ranges);
    try boolean.collect(&collector, parsed, snippet_file, test_ranges);
    return collector.finish();
}

fn applyCandidate(arena: std.mem.Allocator, source: []const u8, m: mutant.Mutant) std.mem.Allocator.Error![]const u8 {
    const start: usize = @intCast(m.span.byte_start);
    const end: usize = @intCast(m.span.byte_end);
    if (start > end or end > source.len) return arena.dupe(u8, source);
    return std.fmt.allocPrint(arena, "{s}{s}{s}", .{ source[0..start], m.replacement, source[end..] });
}

fn findBlockByLine(blocks: []const block.Block, line: u32) ?block.Block {
    for (blocks) |b| {
        if (b.line_start == line) return b;
    }
    return null;
}
