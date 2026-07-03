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
const optional = @import("../mutators/optional.zig");
const error_path = @import("../mutators/error_path.zig");
const integer_boundary = @import("../mutators/integer_boundary.zig");
const loop_boundary = @import("../mutators/loop_boundary.zig");
const runner = @import("../runner.zig");
const mutant_runner = @import("../mutant_runner.zig");
const report = @import("../report.zig");
const block = @import("block.zig");
const parser = @import("parser.zig");
const extractor = @import("extractor.zig");
const case_mod = @import("case.zig");
const mutation_id = @import("mutation_id.zig");

pub const schema_version = "zentinel.doctest.mutation_experiment.v1";

const snippet_file = "doctest_snippet.zig";
const mutate_command = "zig test src/doctest.zig";

pub const StableCommand = struct {
    original: []const u8,
    argv: []const []const u8,
    cwd: []const u8,
    environment_policy: []const u8 = "minimal",
    shell: bool = false,
};

/// Injected runner for a mutated doctest snippet. The real runner writes the
/// snippet into a generated workspace and runs `zig test`; tests inject a mock.
pub const SnippetRunner = struct {
    ctx: *anyopaque,
    runFn: *const fn (ctx: *anyopaque, mutated_source: []const u8) runner.RawOutcome,
    commandFn: ?*const fn (ctx: *anyopaque, mutated_source: []const u8) StableCommand = null,

    pub fn run(self: SnippetRunner, mutated_source: []const u8) runner.RawOutcome {
        return self.runFn(self.ctx, mutated_source);
    }

    pub fn command(self: SnippetRunner, mutated_source: []const u8) StableCommand {
        if (self.commandFn) |f| return f(self.ctx, mutated_source);
        return mutationCommand();
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
        const producer = block.findByLine(parsed.blocks, c.anchor_line) orelse continue;
        const snippet = producer.content;
        summary.cases += 1;

        if (!try hasBehavioralAssertion(arena, snippet)) {
            summary.skipped_cases += 1;
            try cases.append(arena, skippedCase(c, "no_behavioral_assertion"));
            continue;
        }

        // Preflight: a normal doctest failure prevents mutation for this case.
        const pre = try classify(arena, snippet_runner.run(snippet), mutationCommand());
        if (pre.status != .passed) {
            summary.skipped_cases += 1;
            try cases.append(arena, skippedCase(c, "normal_doctest_did_not_pass"));
            continue;
        }

        const cands = try candidates(arena, snippet);
        var outcomes: std.ArrayList(MutantOutcome) = .empty;
        for (cands) |m| {
            const mutated = try applyCandidate(arena, snippet, m);
            const command = snippet_runner.command(mutated);
            const cr = try classify(arena, snippet_runner.run(mutated), command);
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

fn classify(arena: std.mem.Allocator, raw: runner.RawOutcome, command: StableCommand) std.mem.Allocator.Error!report.CommandResult {
    return runner.classifyCommand(arena, .mutant, command.original, command.argv, command.cwd, raw);
}

/// A doctest has a behavioral assertion when it declares a `test` and uses a
/// `try`-based check or an `expect`-prefixed call (the canonical std.testing
/// idioms); otherwise it cannot kill any mutant. Tokenized rather than
/// substring-matched, so the words `test`/`expect` appearing in a comment or a
/// string literal never count as an assertion (and vice versa).
fn hasBehavioralAssertion(arena: std.mem.Allocator, snippet: []const u8) std.mem.Allocator.Error!bool {
    const buf = try arena.dupeZ(u8, snippet);
    var tok = std.zig.Tokenizer.init(buf);
    var saw_test = false;
    var saw_assertion = false;
    while (true) {
        const t = tok.next();
        switch (t.tag) {
            .eof => break,
            .keyword_test => saw_test = true,
            .keyword_try => saw_assertion = true,
            .identifier => {
                if (std.mem.startsWith(u8, buf[t.loc.start..t.loc.end], "expect")) saw_assertion = true;
            },
            else => {},
        }
    }
    return saw_test and saw_assertion;
}

fn candidates(arena: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]mutant.Mutant {
    return switch (try candidatesOrParseError(arena, source)) {
        .ok => |items| items,
        .parse_error => &.{},
        .invalid_candidate => &.{},
    };
}

fn applyCandidate(arena: std.mem.Allocator, source: []const u8, m: mutant.Mutant) std.mem.Allocator.Error![]const u8 {
    const start: usize = @intCast(m.span.byte_start);
    const end: usize = @intCast(m.span.byte_end);
    if (start > end or end > source.len) return arena.dupe(u8, source);
    return std.fmt.allocPrint(arena, "{s}{s}{s}", .{ source[0..start], m.replacement, source[end..] });
}

// --- Stabilized mutation-aware doctest report -------------------
//
// The stabilized surface emits `zentinel.doctest.report.v1` mutation entries
// (`case.kind = "mutation"`) with durable `dm_...` ids, `ds_...` survivor refs
// (survived only), and closed `runner_evidence` including `failure_kind`. It is
// opt-in (the caller must pass `opted_in = true`) and a normal doctest failure
// blocks mutation-aware execution for that case. The experimental report above
// is left unchanged.

pub const StableError = error{NotOptedIn} || std.mem.Allocator.Error;

pub const StableRunnerEvidence = struct {
    status: []const u8,
    command: StableCommand,
    exit_code: ?i64,
    timed_out: bool,
    failure_kind: []const u8,
    stdout_excerpt: []const u8,
    stderr_excerpt: []const u8,
    failure_summary: []const u8,
    skip_reason: ?[]const u8,
};

pub const StableRun = struct {
    id: []const u8 = "doctest_mutation_run",
    status: []const u8 = "completed",
    @"error": ?[]const u8 = null,
    zentinel_version: []const u8 = "0.0.0",
    zig_version: []const u8 = "0.16.0",
    command: []const u8 = "zentinel doctest --mutate",
    project_root: []const u8 = "<project>",
    started_at: []const u8 = "1970-01-01T00:00:00Z",
    duration_ms: u64 = 0,
};

pub const StableAdvisory = struct {
    ai: ?[]const u8 = null,
};

pub const StableMutation = struct {
    doctest_case_id: []const u8,
    mutant_id: []const u8,
    operator: []const u8,
    operator_stability: []const u8,
    backend: []const u8,
    backend_stability: []const u8,
    doc_file: []const u8,
    doc_line: u32,
    source_ref: []const u8,
    mutated_diff: []const []const u8,
    survivor_ref: ?[]const u8,
    runner_evidence: StableRunnerEvidence,
};

pub const StableMutationCase = struct {
    id: []const u8,
    file: []const u8,
    line_start: u32,
    line_end: u32,
    source_ref: []const u8,
    block_refs: []const []const u8,
    kind: []const u8 = "mutation",
    status: []const u8,
    expectation: ?[]const u8 = null,
    command: ?StableCommand = null,
    result: ?[]const u8 = null,
    diagnostics: []const []const u8 = &.{},
    advisory: StableAdvisory = .{},
    mutation: StableMutation,
};

pub const StableMutationSummary = struct {
    total: u64 = 0,
    killed: u64 = 0,
    survived: u64 = 0,
    compile_error: u64 = 0,
    compiler_crash: u64 = 0,
    timeout: u64 = 0,
    skipped: u64 = 0,
    invalid: u64 = 0,
};

pub const StableSummary = struct {
    total: u64 = 0,
    passed: u64 = 0,
    failed: u64 = 0,
    compile_error: u64 = 0,
    expected_compile_error: u64 = 0,
    timeout: u64 = 0,
    skipped: u64 = 0,
    invalid: u64 = 0,
    mutation: StableMutationSummary,
};

/// The mutation-aware extension counted separately from the top-level
/// (preflight, non-mutation) doctest summary.
pub const StableReport = struct {
    schema_version: []const u8 = "zentinel.doctest.report.v1",
    run: StableRun = .{},
    summary: StableSummary,
    cases: []const StableMutationCase,
};

fn mutationCommand() StableCommand {
    return .{ .original = mutate_command, .argv = &.{ "zig", "test", "src/doctest.zig" }, .cwd = "." };
}

fn mutatedDiff(arena: std.mem.Allocator, m: mutant.Mutant) std.mem.Allocator.Error![]const []const u8 {
    const buf = try arena.alloc([]const u8, 2);
    buf[0] = try std.fmt.allocPrint(arena, "- {s}", .{m.original});
    buf[1] = try std.fmt.allocPrint(arena, "+ {s}", .{m.replacement});
    return buf;
}

fn lessById(_: void, a: StableMutationCase, b: StableMutationCase) bool {
    return std.mem.order(u8, a.id, b.id) == .lt;
}

fn blockRefs(arena: std.mem.Allocator, c: case_mod.Case) std.mem.Allocator.Error![]const []const u8 {
    return arena.dupe([]const u8, &.{c.source_ref});
}

fn skippedMutationCase(arena: std.mem.Allocator, c: case_mod.Case, reason: []const u8) std.mem.Allocator.Error!StableMutationCase {
    const ident = mutation_id.Identity{
        .doctest_case_id = c.id,
        .mutant_id = "",
        .operator = "",
        .doc_file = c.file,
        .source_ref = c.source_ref,
        .normalized_mutated_diff = "",
    };
    return .{
        .id = try arena.dupe(u8, &mutation_id.mutationCaseId(ident)),
        .file = c.file,
        .line_start = c.line_start,
        .line_end = c.line_end,
        .source_ref = c.source_ref,
        .block_refs = try blockRefs(arena, c),
        .status = "skipped",
        .mutation = .{
            .doctest_case_id = c.id,
            .mutant_id = "",
            .operator = "",
            .operator_stability = "stable",
            .backend = "ast",
            .backend_stability = "stable",
            .doc_file = c.file,
            .doc_line = c.line_start,
            .source_ref = c.source_ref,
            .mutated_diff = &.{},
            .survivor_ref = null,
            .runner_evidence = .{
                .status = "skipped",
                .command = mutationCommand(),
                .exit_code = null,
                .timed_out = false,
                .failure_kind = "skipped",
                .stdout_excerpt = "",
                .stderr_excerpt = "",
                .failure_summary = "",
                .skip_reason = reason,
            },
        },
    };
}

fn invalidMutationCase(arena: std.mem.Allocator, c: case_mod.Case, reason: []const u8) std.mem.Allocator.Error!StableMutationCase {
    const ident = mutation_id.Identity{
        .doctest_case_id = c.id,
        .mutant_id = "",
        .operator = "backend_parse",
        .doc_file = c.file,
        .source_ref = c.source_ref,
        .normalized_mutated_diff = reason,
    };
    return .{
        .id = try arena.dupe(u8, &mutation_id.mutationCaseId(ident)),
        .file = c.file,
        .line_start = c.line_start,
        .line_end = c.line_end,
        .source_ref = c.source_ref,
        .block_refs = try blockRefs(arena, c),
        .status = "invalid",
        .mutation = .{
            .doctest_case_id = c.id,
            .mutant_id = "",
            .operator = "backend_parse",
            .operator_stability = "stable",
            .backend = "ast",
            .backend_stability = "stable",
            .doc_file = c.file,
            .doc_line = c.line_start,
            .source_ref = c.source_ref,
            .mutated_diff = &.{},
            .survivor_ref = null,
            .runner_evidence = .{
                .status = "invalid",
                .command = mutationCommand(),
                .exit_code = null,
                .timed_out = false,
                .failure_kind = "invalid",
                .stdout_excerpt = "",
                .stderr_excerpt = "",
                .failure_summary = reason,
                .skip_reason = null,
            },
        },
    };
}

const CandidateSet = union(enum) {
    ok: []mutant.Mutant,
    parse_error,
    invalid_candidate,
};

fn candidatesOrParseError(arena: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error!CandidateSet {
    var parsed = ast_backend.parse(arena, snippet_file, source) catch return .parse_error;
    if (!parsed.ok()) return .parse_error;
    var collector = ast_backend.Collector.init(arena);
    const test_ranges = try ast_backend.testDeclRanges(parsed, arena);
    try arithmetic.collect(&collector, parsed, snippet_file, test_ranges);
    try comparison.collect(&collector, parsed, snippet_file, test_ranges);
    try logical.collect(&collector, parsed, snippet_file, test_ranges);
    try boolean.collect(&collector, parsed, snippet_file, test_ranges);
    // Phase-2 stable collectors, matching the run/list-mutants pipeline
    // (run_command.generateCandidates). Without these the doctest --mutate path
    // silently emitted zero mutants for a snippet whose only mutable construct is
    // an optional/error-path/integer-boundary/loop-boundary form, falsely
    // reporting a weak documentation example as fully covered.
    try optional.collect(&collector, parsed, snippet_file, test_ranges);
    try error_path.collect(&collector, parsed, snippet_file, test_ranges);
    try integer_boundary.collect(&collector, parsed, snippet_file, test_ranges);
    try loop_boundary.collect(&collector, parsed, snippet_file, test_ranges);
    if (collector.invalidCount() > 0) return .invalid_candidate;
    return .{ .ok = try collector.finish() };
}

/// Run the stabilized mutation-aware pass over `source`. Opt-in only; a normal
/// doctest failure (or a case with no behavioral assertion) yields a single
/// `skipped` mutation entry and never executes mutants for that case. Output is
/// deterministic and sorted by durable `dm_...` id.
pub fn stableMutationRun(
    arena: std.mem.Allocator,
    file: []const u8,
    source: []const u8,
    snippet_runner: SnippetRunner,
    opted_in: bool,
) StableError!StableReport {
    if (!opted_in) return error.NotOptedIn;

    const parsed = try parser.parse(arena, file, source);
    const extracted = try extractor.extract(arena, file, parsed.blocks, parsed.diagnostics);

    var cases: std.ArrayList(StableMutationCase) = .empty;
    var mutation_summary = StableMutationSummary{};

    for (extracted.cases) |c| {
        if (c.kind != .zig_test) continue;
        const producer = block.findByLine(parsed.blocks, c.anchor_line) orelse continue;
        const snippet = producer.content;

        if (!try hasBehavioralAssertion(arena, snippet)) {
            try cases.append(arena, try skippedMutationCase(arena, c, "no_behavioral_assertion"));
            mutation_summary.total += 1;
            mutation_summary.skipped += 1;
            continue;
        }
        // Preflight gate: a normal doctest failure blocks mutation-aware
        // execution for this case.
        const pre = try classify(arena, snippet_runner.run(snippet), mutationCommand());
        if (pre.status != .passed) {
            try cases.append(arena, try skippedMutationCase(arena, c, "normal_doctest_did_not_pass"));
            mutation_summary.total += 1;
            mutation_summary.skipped += 1;
            continue;
        }

        const cands = switch (try candidatesOrParseError(arena, snippet)) {
            .ok => |items| items,
            .parse_error => {
                const reason = "backend: could not parse doctest mutation snippet";
                try cases.append(arena, try invalidMutationCase(arena, c, reason));
                mutation_summary.total += 1;
                mutation_summary.invalid += 1;
                continue;
            },
            .invalid_candidate => {
                const reason = "ZNTL_MUTATOR_INVALID_CANDIDATE: AST backend emitted an invalid mutation candidate";
                try cases.append(arena, try invalidMutationCase(arena, c, reason));
                mutation_summary.total += 1;
                mutation_summary.invalid += 1;
                continue;
            },
        };
        for (cands) |m| {
            const mutated = try applyCandidate(arena, snippet, m);
            const command = snippet_runner.command(mutated);
            const cr = try classify(arena, snippet_runner.run(mutated), command);
            const single = try arena.dupe(report.CommandResult, &.{cr});
            const mr = mutant_runner.classifyFromCommands(m.id, .Debug, single);

            const diff = try mutatedDiff(arena, m);
            const norm = try mutation_id.normalizeDiff(arena, diff);
            const ident = mutation_id.Identity{
                .doctest_case_id = c.id,
                .mutant_id = m.id,
                .operator = m.operator,
                .doc_file = file,
                .source_ref = c.source_ref,
                .normalized_mutated_diff = norm,
            };
            const dm = try arena.dupe(u8, &mutation_id.mutationCaseId(ident));
            // Survivor refs only for survived mutants; every other status is null.
            const survivor: ?[]const u8 = if (mr.status == .survived)
                try arena.dupe(u8, &mutation_id.survivorRef(ident))
            else
                null;

            mutation_summary.total += 1;
            switch (mr.status) {
                .killed => mutation_summary.killed += 1,
                .survived => mutation_summary.survived += 1,
                .compile_error => mutation_summary.compile_error += 1,
                .compiler_crash => mutation_summary.compiler_crash += 1,
                .timeout => mutation_summary.timeout += 1,
                .skipped => mutation_summary.skipped += 1,
                .invalid => mutation_summary.invalid += 1,
            }

            try cases.append(arena, .{
                .id = dm,
                .file = c.file,
                .line_start = c.line_start,
                .line_end = c.line_end,
                .source_ref = c.source_ref,
                .block_refs = try blockRefs(arena, c),
                .status = @tagName(mr.status),
                .mutation = .{
                    .doctest_case_id = c.id,
                    .mutant_id = m.id,
                    .operator = m.operator,
                    .operator_stability = @tagName(m.operator_stability),
                    .backend = @tagName(m.backend),
                    .backend_stability = @tagName(m.backend_stability),
                    .doc_file = c.file,
                    .doc_line = c.line_start,
                    .source_ref = c.source_ref,
                    .mutated_diff = diff,
                    .survivor_ref = survivor,
                    .runner_evidence = .{
                        .status = @tagName(mr.status),
                        .command = command,
                        .exit_code = cr.exit_code,
                        .timed_out = cr.timed_out,
                        .failure_kind = @tagName(cr.failure_kind),
                        .stdout_excerpt = cr.evidence.stdout_excerpt,
                        .stderr_excerpt = cr.evidence.stderr_excerpt,
                        .failure_summary = cr.evidence.failure_summary,
                        .skip_reason = null,
                    },
                },
            });
        }
    }

    const out = try cases.toOwnedSlice(arena);
    std.mem.sort(StableMutationCase, out, {}, lessById);
    return .{ .summary = .{ .mutation = mutation_summary }, .cases = out };
}

pub fn stableToJson(arena: std.mem.Allocator, r: StableReport) std.mem.Allocator.Error![]u8 {
    return std.json.Stringify.valueAlloc(arena, r, .{ .whitespace = .indent_2 });
}

/// Produce the persistable stable mutation-aware doctest report JSON for one doc:
/// the report `zentinel doctest --mutate` writes to the survivor report path so
/// `doctest explain-survivor` can resolve a `ds_` survivor. The explicit
/// `--mutate` invocation is the opt-in, so this always runs opted-in.
pub fn mutateReportJson(arena: std.mem.Allocator, file: []const u8, source: []const u8, snippet_runner: SnippetRunner) std.mem.Allocator.Error![]u8 {
    const r = stableMutationRun(arena, file, source, snippet_runner, true) catch |err| switch (err) {
        error.NotOptedIn => unreachable, // always opted in from this entry point
        error.OutOfMemory => return error.OutOfMemory,
    };
    return stableToJson(arena, r);
}
