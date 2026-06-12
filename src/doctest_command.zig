// Layer: deterministic_core
//
// `zentinel doctest` orchestration (docs/DOCTEST_SPEC.md, docs/CLI_SPEC.md). It
// reuses the doctest parser, extractor, runner, normalizer, matcher, and
// snapshot modules to execute normal documentation doctests and assemble a
// deterministic zentinel.doctest.report.v1 report. Pure: process execution and
// workspace materialization are injected (the CLI wires the real adapters; tests
// inject mocks). No mutation-aware behavior, cache, or AI.
const std = @import("std");
const block = @import("doctest/block.zig");
const parser = @import("doctest/parser.zig");
const extractor = @import("doctest/extractor.zig");
const case_mod = @import("doctest/case.zig");
const runner = @import("doctest/runner.zig");
const proc = @import("runner.zig");
const workspace = @import("doctest/workspace.zig");
const normalizer = @import("doctest/normalizer.zig");
const matcher = @import("doctest/matcher.zig");
const snap = @import("doctest/snapshot.zig");
const doc_report = @import("doctest/report.zig");

pub const Format = enum { text, json };

pub const Options = struct {
    file: ?[]const u8 = null,
    format: Format = .text,
    case_ref: ?[]const u8 = null,
};

pub const ParseError = error{ MissingValue, UnknownOption, InvalidFormat, UnsupportedSubcommand };

/// Parse `zentinel doctest` arguments. AI/mutation subcommands (explain, suggest,
/// review-snapshot, suggest-missing, explain-survivor, --mutate) are not owned by
/// this task and are rejected as unsupported.
pub fn parseArgs(args: []const []const u8) ParseError!Options {
    var opts: Options = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--file")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.file = args[i];
        } else if (std.mem.eql(u8, a, "--format")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            if (std.mem.eql(u8, args[i], "text")) {
                opts.format = .text;
            } else if (std.mem.eql(u8, args[i], "json")) {
                opts.format = .json;
            } else return error.InvalidFormat;
        } else if (std.mem.eql(u8, a, "--case")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.case_ref = args[i];
        } else if (std.mem.eql(u8, a, "--no-color")) {
            // Accepted for CLI uniformity (root.zig accepts `--no-color` globally
            // too), but a pure no-op: doctest renderers never emit ANSI color, so
            // there is nothing to suppress and nothing to store. Threading a
            // dead flag into renderText would only re-create an unused parameter.
        } else if (std.mem.startsWith(u8, a, "--")) {
            return error.UnknownOption;
        } else {
            // A bare token is an unsupported subcommand (explain/suggest/...).
            return error.UnsupportedSubcommand;
        }
    }
    return opts;
}

/// How a `zentinel doctest <args>` invocation dispatches. `mutate` is the
/// experimental flag mode; the named variants are the advisory-AI subcommands;
/// `parse` is the ordinary doctest run (handled by `parseArgs`).
pub const Route = enum { mutate, explain, suggest, review_snapshot, suggest_missing, explain_survivor, parse };

/// Decide the doctest dispatch for `args`. A recognized named subcommand in the
/// FIRST positional slot wins BEFORE the `--mutate` flag scan, so e.g.
/// `doctest suggest --mutate` runs the suggest flow rather than being hijacked by
/// `--mutate` appearing later and rejected as a bogus mutate option.
pub fn route(args: []const []const u8) Route {
    if (args.len > 0 and !std.mem.startsWith(u8, args[0], "-")) {
        const sub = args[0];
        if (std.mem.eql(u8, sub, "explain")) return .explain;
        if (std.mem.eql(u8, sub, "suggest")) return .suggest;
        if (std.mem.eql(u8, sub, "review-snapshot")) return .review_snapshot;
        if (std.mem.eql(u8, sub, "suggest-missing")) return .suggest_missing;
        if (std.mem.eql(u8, sub, "explain-survivor")) return .explain_survivor;
    }
    // Experimental opt-in: `--mutate` anywhere (e.g. `doctest --mutate --file X`)
    // selects the mutation-aware doctest prototype -- but only when args[0] is not
    // a named subcommand (handled above).
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--mutate")) return .mutate;
    }
    return .parse;
}

pub const Observation = struct {
    run_id: []const u8,
    started_at: []const u8,
    zentinel_version: []const u8,
    zig_version: []const u8,
    project_root: []const u8,
    command: []const u8,
};

pub const Deps = struct {
    executor: proc.Executor,
    provider: workspace.Provider,
};

pub const Output = struct {
    report: doc_report.Report,
    exit_code: u8,
};

// A per-case workspace-creation failure is isolated as an `.invalid` case by the
// runner, so it never reaches here; the only errors that abort the whole
// run are an unresolved `--case` selector and OOM.
pub const RunError = error{CaseNotFound} || std.mem.Allocator.Error;

/// Execute normal doctests over `doc_source` and assemble the report.
pub fn run(
    arena: std.mem.Allocator,
    options: Options,
    doc_file: []const u8,
    doc_source: []const u8,
    obs: Observation,
    deps: Deps,
) RunError!Output {
    const parsed = try parser.parse(arena, doc_file, doc_source);
    const extracted = try extractor.extract(arena, doc_file, parsed.blocks, parsed.diagnostics);

    var selected: []const case_mod.Case = extracted.cases;
    if (options.case_ref) |ref| {
        selected = try selectByRef(arena, extracted.cases, doc_file, ref);
    }

    const norm_opts = normalizer.Options{
        .project_root = if (std.mem.eql(u8, obs.project_root, ".")) "" else obs.project_root,
    };

    var cases: std.ArrayList(doc_report.Case) = .empty;
    for (selected) |c| {
        try cases.append(arena, try runCase(arena, c, parsed.blocks, deps, norm_opts));
    }
    const case_slice = try cases.toOwnedSlice(arena);
    doc_report.sortCases(case_slice);

    const report: doc_report.Report = .{
        .run = .{
            .id = obs.run_id,
            .status = .completed,
            .@"error" = null,
            .zentinel_version = obs.zentinel_version,
            .zig_version = obs.zig_version,
            .command = obs.command,
            .project_root = obs.project_root,
            .started_at = obs.started_at,
            .duration_ms = 0,
        },
        .summary = doc_report.summarize(case_slice),
        .cases = case_slice,
    };
    return .{ .report = report, .exit_code = doc_report.exitCode(report) };
}

fn runCase(
    arena: std.mem.Allocator,
    c: case_mod.Case,
    blocks: []const block.Block,
    deps: Deps,
    norm_opts: normalizer.Options,
) RunError!doc_report.Case {
    const producer = findBlockByLine(blocks, c.anchor_line) orelse blocks[0];
    const ctx = runner.Context{
        .arena = arena,
        .root = ".",
        .zig_version = "0.16.0",
        .executor = deps.executor,
        .provider = deps.provider,
    };
    const cr = try runner.runCase(ctx, c, producer.content);

    var status = cr.status;
    var snapshot: ?doc_report.Snapshot = null;
    var expectation: ?doc_report.Expectation = null;

    // Match EVERY following expectation block (a case may carry more than one,
    // e.g. `text output` plus `diagnostic expected`). All must match; the first
    // mismatch -- or, if all match, the first expectation -- is recorded as the
    // snapshot evidence. Each block is matched against the stream appropriate for
    // the case kind / mode (see actualOutputFor): matching the wrong stream is a
    // false-pass.
    if (c.block_refs.len > 1 and status != .invalid and status != .skipped) {
        var all_matched = true;
        for (c.block_refs[1..]) |ref| {
            const exp = findBlockByLine(blocks, lineOfRef(ref)) orelse continue;
            const mode = matchModeFor(exp);
            const actual = actualOutputFor(c.kind, mode, cr);
            const sr = try snap.compare(arena, c.id, c.file, c.anchor_line, mode, exp.content, actual.text, norm_opts);
            // Default to recording the first expectation; once a mismatch is seen,
            // capture that one instead so the report points at the actual failure.
            if (snapshot == null or (all_matched and !sr.matched)) {
                expectation = .{ .mode = mode, .block_ref = ref };
                snapshot = .{
                    .expected_excerpt = sr.expected_excerpt,
                    .actual_excerpt = sr.actual_excerpt,
                    .normalized_expected_excerpt = sr.normalized_expected,
                    .normalized_actual_excerpt = sr.normalized_actual,
                    .match_mode = mode,
                    .expected_block_ref = ref,
                    .actual_ref = actual.ref,
                    .matched = sr.matched,
                };
            }
            if (!sr.matched) all_matched = false;
        }
        // A mismatch demotes a passing verdict. A `zig compile_fail` case passes
        // as `expected_compile_error`; a non-matching expected diagnostic must
        // demote it to `compile_error` (docs/DOCTEST_SPEC.md), not stay green.
        // Other passing cases (including config_fail, which passes when validation
        // fails as expected) demote to `failed`.
        if (!all_matched) status = switch (status) {
            .expected_compile_error => .compile_error,
            .passed => .failed,
            else => status,
        };
    }

    const diags = try arena.alloc(doc_report.Diagnostic, cr.diagnostics.len);
    for (cr.diagnostics, 0..) |d, i| diags[i] = .{ .code = d.code, .message = d.message };

    var command: ?doc_report.Command = null;
    if (cr.command) |orig| {
        command = .{
            .original = orig,
            .argv = cr.argv orelse &.{},
            .cwd = ".",
        };
    }

    const result: ?doc_report.Result = if (cr.command != null or producesResult(c.kind)) .{
        .exit_code = cr.exit_code,
        .timed_out = cr.timed_out,
        .duration_ms = 0,
        .stdout_excerpt = cr.stdout_excerpt,
        .stderr_excerpt = cr.stderr_excerpt,
        .normalized_stdout_excerpt = try normalizer.normalize(arena, cr.stdout_excerpt, norm_opts),
        .normalized_stderr_excerpt = try normalizer.normalize(arena, cr.stderr_excerpt, norm_opts),
        .snapshot = snapshot,
        .failure_summary = failureSummary(status),
    } else null;

    return .{
        .id = c.id,
        .file = c.file,
        .line_start = c.line_start,
        .line_end = c.line_end,
        .source_ref = c.source_ref,
        .block_refs = c.block_refs,
        .kind = c.kind,
        .status = status,
        .expectation = expectation,
        .command = command,
        .result = result,
        .diagnostics = diags,
        .advisory = .{},
    };
}

fn producesResult(kind: case_mod.CaseKind) bool {
    return switch (kind) {
        .zig_compile_pass, .zig_test, .zig_compile_fail, .cli => true,
        .config, .config_fail, .mutation => false,
    };
}

fn failureSummary(status: doc_report.Status) []const u8 {
    return switch (status) {
        .passed, .expected_compile_error, .skipped => "",
        .failed => "doctest output or command failed",
        .compile_error => "doctest compilation failed",
        .timeout => "doctest timed out",
        .invalid => "invalid doctest case",
    };
}

/// Derive a matcher mode from an expectation block's tags. text output defaults
/// to exact; json expected defaults to json; subset/contains/unordered refine it.
pub fn matchModeFor(b: block.Block) matcher.Mode {
    // A `diagnostic expected` block matches a compiler/config/runtime diagnostic
    // with line/column numbers collapsed (matcher.diagnosticText), regardless of
    // the producer language.
    if (b.language == .diagnostic) return .diagnostic;
    if (b.language == .json) {
        return switch (b.match_mode) {
            .subset => .json_subset,
            .unordered => .json_unordered,
            else => .json,
        };
    }
    return switch (b.match_mode) {
        .contains => .contains,
        .regex => .regex,
        else => .exact,
    };
}

const ActualOutput = struct { text: []const u8, ref: doc_report.ActualRef };

/// Choose which captured stream an expectation block is matched against, plus the
/// `actual_ref` recorded in the report. Compiler diagnostics from a
/// `zig compile_fail` case, and any `diagnostic`-mode expectation, live on stderr;
/// config validation diagnostics are routed to the stdout slot by the runner;
/// everything else matches stdout (the program's primary output). Matching the
/// wrong stream is a false-pass: a compile-fail diagnostic compared against the
/// (empty) stdout would vacuously satisfy a `contains` expectation.
fn actualOutputFor(kind: case_mod.CaseKind, mode: matcher.Mode, cr: runner.CaseResult) ActualOutput {
    if (mode == .diagnostic) {
        // The runner places a config validation diagnostic on the stdout slot;
        // compiler/runtime diagnostics are on stderr.
        if (kind == .config or kind == .config_fail) return .{ .text = cr.stdout_excerpt, .ref = .diagnostic };
        return .{ .text = cr.stderr_excerpt, .ref = .diagnostic };
    }
    return switch (kind) {
        .zig_compile_fail => .{ .text = cr.stderr_excerpt, .ref = .stderr },
        // runConfig formats the validation diagnostic into the stdout slot.
        .config, .config_fail => .{ .text = cr.stdout_excerpt, .ref = .stdout },
        else => .{ .text = cr.stdout_excerpt, .ref = .stdout },
    };
}

fn findBlockByLine(blocks: []const block.Block, line: u32) ?block.Block {
    for (blocks) |b| {
        if (b.line_start == line) return b;
    }
    return null;
}

fn lineOfRef(ref: []const u8) u32 {
    // ref is "file:line[:label]"; take the digit run after the first ':'.
    const first = std.mem.indexOfScalar(u8, ref, ':') orelse return 0;
    var end = first + 1;
    while (end < ref.len and ref[end] >= '0' and ref[end] <= '9') : (end += 1) {}
    // Parse with a checked routine, not a hand-rolled `n = n*10 + d` accumulator:
    // an out-of-range or overlong numeric ref must resolve to line 0 (which matches
    // no real 1-based anchor -> CaseNotFound) rather than overflow into a
    // `panic: integer overflow` (Debug/ReleaseSafe) or a wrapped, wrong line
    // (ReleaseFast). Mirrors the already-hardened src/ai/doctest_command.zig.
    return std.fmt.parseInt(u32, ref[first + 1 .. end], 10) catch 0;
}

/// Resolve a `--case` selector: a durable `dt_...` id or an anchor-line
/// `file:line[:label]` source ref. Source refs resolve only against a case
/// anchor line, so a line pointing only at a secondary expectation block does
/// not match any case and yields CaseNotFound.
fn selectByRef(arena: std.mem.Allocator, cases: []const case_mod.Case, doc_file: []const u8, ref: []const u8) RunError![]const case_mod.Case {
    var match: ?case_mod.Case = null;
    if (std.mem.startsWith(u8, ref, "dt_")) {
        for (cases) |c| {
            if (std.mem.eql(u8, c.id, ref)) match = c;
        }
    } else {
        const file_end = std.mem.indexOfScalar(u8, ref, ':') orelse return error.CaseNotFound;
        const ref_file = ref[0..file_end];
        const line = lineOfRef(ref);
        for (cases) |c| {
            if (std.mem.eql(u8, c.file, ref_file) and c.anchor_line == line) match = c;
        }
        _ = doc_file;
    }
    const m = match orelse return error.CaseNotFound;
    const out = try arena.alloc(case_mod.Case, 1);
    out[0] = m;
    return out;
}

// --- Text rendering --------------------------------------------------------

pub fn renderText(arena: std.mem.Allocator, report: doc_report.Report) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "doctest: {d} cases\n", .{report.summary.total}));
    try out.appendSlice(arena, try std.fmt.allocPrint(
        arena,
        "  passed={d} failed={d} compile_error={d} expected_compile_error={d} timeout={d} skipped={d} invalid={d}\n",
        .{ report.summary.passed, report.summary.failed, report.summary.compile_error, report.summary.expected_compile_error, report.summary.timeout, report.summary.skipped, report.summary.invalid },
    ));
    for (report.cases) |c| {
        switch (c.status) {
            .passed, .skipped, .expected_compile_error => continue,
            else => {},
        }
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "  {s} {s} {s}\n", .{ c.status.toString(), c.id, c.source_ref }));
        for (c.diagnostics) |d| {
            try out.appendSlice(arena, try std.fmt.allocPrint(arena, "    {s}: {s}\n", .{ d.code, d.message }));
        }
    }
    return out.toOwnedSlice(arena);
}
