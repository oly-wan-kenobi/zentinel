// Layer: deterministic_core
//
// `zentinel run` orchestration (docs/CLI_SPEC.md, docs/REPORT_FORMAT.md). Wires
// project model, baseline runner, Phase 1 AST mutators, the patch sandbox, and
// the mutant runner into a single serial flow that produces a deterministic
// report. Pure: process execution and filesystem workspaces are injected (a
// baseline `runner.Executor` and a `MutantRunner`), and source bytes are passed
// in, so the orchestration and report assembly are testable without real
// processes. The presentation adapter wires the real providers for the binary.
const std = @import("std");
const config = @import("config.zig");
const ast_backend = @import("ast_backend.zig");
const mutant = @import("mutant.zig");
const arithmetic = @import("mutators/arithmetic.zig");
const comparison = @import("mutators/comparison.zig");
const logical = @import("mutators/logical.zig");
const boolean = @import("mutators/boolean.zig");
const optional = @import("mutators/optional.zig");
const error_path = @import("mutators/error_path.zig");
const integer_boundary = @import("mutators/integer_boundary.zig");
const loop_boundary = @import("mutators/loop_boundary.zig");
const runner = @import("runner.zig");
const mutant_runner = @import("mutant_runner.zig");
const semantic_filter = @import("semantic_filter.zig");
const report = @import("report.zig");
const command = @import("command.zig");
const test_selection = @import("test_selection.zig");
const cache = @import("cache.zig");
const worker_pool = @import("worker_pool.zig");
const safety_modes = @import("safety_modes.zig");

pub const ReportFormat = enum { text, json, jsonl, junit };

/// One completed mutant's progress facts (docs/CLI_SPEC.md `run` progress).
pub const ProgressEvent = struct {
    status: report.ResultStatus,
    operator: []const u8,
    file: []const u8,
    line: u32,
};

/// Adapter-injected per-mutant progress sink. Called once per mutant as its
/// Phase B result completes -- in completion order, possibly concurrently under
/// `--jobs > 1` -- so the callback must be thread-safe. Progress is advisory
/// stderr output only: it never changes report data, ordering, or exit codes
/// (results stay index-addressed and the report is sorted in Phase C).
pub const Progress = struct {
    ctx: *anyopaque,
    notifyFn: *const fn (ctx: *anyopaque, completed: usize, total: usize, event: ProgressEvent) void,
};

/// Adapter-injected content-addressed result store for cross-run reuse
/// (docs/PERFORMANCE_STRATEGY.md "Caching Strategy"). `get` returns the
/// previously persisted entry bytes for a key (or null on a miss / unreadable
/// entry); `put` persists an entry's bytes under its key. The deterministic core
/// only ever stores POST-REVERIFY terminal verdicts and serves them back, so the
/// store never changes a verdict -- it only skips recomputing one. Filesystem
/// I/O lives entirely in the adapter's implementation (the binary keys entries
/// under `.zig-cache/zentinel/results/<key>.json`); tests inject an in-memory
/// store. `null` (the default) disables reuse without disabling key computation,
/// reproducing the prior metadata-only behavior byte-for-byte.
pub const ResultStore = struct {
    ctx: *anyopaque,
    getFn: *const fn (ctx: *anyopaque, key: []const u8) ?[]const u8,
    putFn: *const fn (ctx: *anyopaque, key: []const u8, bytes: []const u8) void,

    pub fn get(self: ResultStore, key: []const u8) ?[]const u8 {
        return self.getFn(self.ctx, key);
    }
    pub fn put(self: ResultStore, key: []const u8, bytes: []const u8) void {
        self.putFn(self.ctx, key, bytes);
    }
};

pub const Options = struct {
    operator_filter: ?[]const u8 = null,
    mutant_filter: ?[]const u8 = null,
    fail_on_survivors: bool = false,
    report_format: ReportFormat = .text,
    output: ?[]const u8 = null,
    /// Terminal verbosity (docs/CLI_SPEC.md). Affects only the text rendering in
    /// the adapter; never changes deterministic report data.
    verbose: bool = false,
    quiet: bool = false,
    /// Disable the zentinel result cache for this invocation. Reflected only in
    /// cache metadata/policy, never in mutant correctness; Zig build-cache
    /// isolation metadata is unaffected.
    no_cache: bool = false,
    /// Adapter-injected content-addressed result store enabling cross-run result
    /// reuse. `null` (the default) leaves reuse disabled -- keys are still
    /// computed for metadata, but no entry is read or written, so existing
    /// callers behave exactly as before. When set (and the cache is enabled and
    /// the run is single-mode), a terminal post-reverify verdict is served from
    /// the store on a hit (skipping compile+test) and persisted on a miss.
    result_cache: ?ResultStore = null,
    /// Worker count for parallel mutant execution (`--jobs <n>`). When set, it
    /// overrides normalized `run.jobs`. Chooses only concurrency, never report
    /// ordering or mutation semantics; `null` falls back to `run.jobs`.
    jobs: ?usize = null,
    /// Single-invocation safety/optimization mode override (`--mode <...>`).
    /// When set it replaces the configured `zig.modes` for this run and
    /// yields a single-mode report; `null` uses the configured modes.
    mode_override: ?report.Mode = null,
    /// Diff-scoping (docs/PERFORMANCE_STRATEGY.md): the resolved set of
    /// project-relative files mutation is restricted to. `null` = no scoping
    /// (default; reproduces the full run). When non-null, `generateCandidates`
    /// keeps only candidates whose file is in this set; `files` stays complete so
    /// `projectHash`, same-file selection, and the source index are unchanged --
    /// scoping only omits out-of-scope mutants, never alters a retained verdict.
    /// Set by the adapter (resolving the raw inputs below, where git lives) or
    /// directly by tests; the deterministic core never derives it (I-022).
    scope_files: ?[]const []const u8 = null,
    /// Raw diff-scope CLI inputs the adapter resolves into `scope_files`; the
    /// deterministic core ignores them. `--changed-only` (tracked changes vs
    /// HEAD), `--diff <ref>` (`diff_base`), and `--scope-files <csv>`
    /// (`scope_files_csv`) are three mutually exclusive ways to derive ONE set.
    changed_only: bool = false,
    diff_base: ?[]const u8 = null,
    scope_files_csv: ?[]const u8 = null,
    /// Adapter-injected per-mutant progress sink (stderr in the binary). Never
    /// set by `parseArgs`; the adapter leaves it null under `--quiet`.
    progress: ?Progress = null,
};

/// Observation metadata supplied by the caller. Normalized in snapshots/tests.
pub const Observation = struct {
    run_id: []const u8,
    started_at: []const u8,
    project_root: []const u8,
    zentinel_version: []const u8,
    zig_version: []const u8,
    config_hash: []const u8,
    /// Zig compiler cache namespace metadata for cache keys (normalized label).
    zig_cache_namespace: []const u8 = "",
    /// Hash of the minimal command environment actually used for execution.
    environment_hash: []const u8 = "",
    duration_ms: u64 = 0,
};

/// One eligible source file and its bytes (read by the caller).
pub const FileSource = struct {
    path: []const u8,
    source: []const u8,
};

/// Per-mutant execution abstraction. Tests inject a mock returning programmed
/// results; the binary injects a runner that creates a workspace, writes the
/// patched file, runs the configured commands, and classifies.
pub const MutantRunner = struct {
    ctx: *anyopaque,
    runFn: *const fn (ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult,
    runSpecsFn: ?*const fn (ctx: *anyopaque, m: mutant.Mutant, source: []const u8, commands: []const command.Spec, mode: report.Mode) mutant_runner.MutationResult = null,
    /// Optional production adapter that runs a mutant across multiple build modes
    /// in a single reused workspace. When null, `runModes` falls back to a
    /// per-mode `runSpecs` loop. `out.len == modes.len`.
    runModesFn: ?*const fn (ctx: *anyopaque, m: mutant.Mutant, source: []const u8, specs: []const command.Spec, reverify_specs: []const command.Spec, modes: []const report.Mode, out: []report.ResultStatus) void = null,

    pub fn run(self: MutantRunner, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
        return self.runFn(self.ctx, m, source, commands, mode);
    }

    pub fn runSpecs(self: MutantRunner, m: mutant.Mutant, source: []const u8, specs: []const command.Spec, originals: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
        if (self.runSpecsFn) |f| return f(self.ctx, m, source, specs, mode);
        return self.runFn(self.ctx, m, source, originals, mode);
    }

    /// Run one mutant across `modes`, reusing a SINGLE materialized workspace for
    /// all of them (the patched source is build-mode-independent), and writing each
    /// mode's status into `out[k]`. For a mode whose narrowed run survives, a
    /// non-empty `reverify_specs` is re-run in the same workspace to confirm the
    /// verdict against the configured suite (mirrors Phase B.5 per mode). The
    /// production adapter (`runModesFn`) materializes the workspace once; when
    /// absent (test executors), the fallback runs each mode through `runSpecs`,
    /// which is behaviorally identical but re-materializes per call.
    pub fn runModes(
        self: MutantRunner,
        m: mutant.Mutant,
        source: []const u8,
        specs: []const command.Spec,
        originals: []const []const u8,
        reverify_specs: []const command.Spec,
        reverify_originals: []const []const u8,
        modes: []const report.Mode,
        out: []report.ResultStatus,
    ) void {
        if (self.runModesFn) |f| return f(self.ctx, m, source, specs, reverify_specs, modes, out);
        for (modes, 0..) |mode, k| {
            const narrowed = self.runSpecs(m, source, specs, originals, mode);
            out[k] = if (narrowed.status == .survived and reverify_specs.len > 0)
                self.runSpecs(m, source, reverify_specs, reverify_originals, mode).status
            else
                narrowed.status;
        }
    }
};

/// One mutant's fully-resolved execution inputs, assembled serially in Phase A
/// so Phase B only runs the mutant and records its result by index.
const Job = struct {
    candidate: mutant.Mutant,
    source: []const u8,
    commands: []const []const u8,
    command_specs: []const command.Spec,
    selection: report.TestSelection,
};

/// Shared state for the parallel mutant phase. Each worker writes only its own
/// `results[index]` slot, so the worker pool needs no extra synchronization.
const ParallelCtx = struct {
    jobs: []const Job,
    results: []mutant_runner.MutationResult,
    mutant_executor: MutantRunner,
    mode: report.Mode,
    /// Per-job result-cache hit flags. A hit index already has its `results` slot
    /// filled from the store (a POST-REVERIFY terminal verdict), so its mutant is
    /// neither run here nor reverified in Phase B.5 -- the whole point of reuse is
    /// to skip compile+test. `&.{}` means "no reuse" (every index a miss).
    hits: []const bool = &.{},
    /// Optional progress sink plus the shared completion counter feeding it.
    /// The counter is the only cross-worker progress state; each notify call
    /// gets a unique completed value in [1, jobs.len].
    progress: ?Progress = null,
    completed: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
};

/// Whether index `i` is a result-cache hit (its result is already in `results`).
fn isHit(hits: []const bool, i: usize) bool {
    return i < hits.len and hits[i];
}

/// Worker-pool task: run one mutant and store its result at the matching index.
/// The injected runner isolates each mutant in its own content-addressed
/// workspace, so concurrent workers never share a workspace, cache, or output.
/// A result-cache hit is skipped entirely (its `results` slot is already the
/// served verdict). Progress (when injected) is emitted in completion order for
/// both run and reused mutants, so the completion count still reaches `jobs.len`;
/// the report's determinism is untouched because results stay index-addressed.
fn runOneMutant(ctx: *anyopaque, index: usize, slot: usize) void {
    _ = slot;
    const pc: *ParallelCtx = @ptrCast(@alignCast(ctx));
    const job = pc.jobs[index];
    if (!isHit(pc.hits, index)) {
        pc.results[index] = pc.mutant_executor.runSpecs(job.candidate, job.source, job.command_specs, job.commands, pc.mode);
    }
    if (pc.progress) |p| {
        const done = pc.completed.fetchAdd(1, .monotonic) + 1;
        p.notifyFn(p.ctx, done, pc.jobs.len, .{
            .status = pc.results[index].status,
            .operator = job.candidate.operator,
            .file = job.candidate.file,
            .line = job.candidate.span.line_start,
        });
    }
}

/// Shared state for the parallel Phase B.5 reverification. Each worker writes only
/// its disjoint `out[index]`; the raw-arena merge runs serially in the caller so
/// the (non-thread-safe) arena is never touched off the worker threads.
const ReverifyCtx = struct {
    jobs: []const Job,
    results: []const mutant_runner.MutationResult,
    out: []?mutant_runner.MutationResult,
    reverify_specs: []const command.Spec,
    cfg_test_commands: []const []const u8,
    mutant_executor: MutantRunner,
    mode: report.Mode,
    /// Per-job result-cache hit flags. A served verdict is ALREADY post-reverify
    /// (only post-reverify terminal verdicts are ever stored), so a hit must not
    /// be reverified again -- doing so would re-run the suite the cache exists to
    /// skip and could overwrite the authoritative cached verdict.
    hits: []const bool = &.{},
};

/// Worker-pool task: reverify one narrowed survivor against the configured suite.
/// Result-cache hits (already post-reverify), non-survivors, and survivors whose
/// selection did not narrow are no-ops.
fn reverifyOneMutant(ctx: *anyopaque, index: usize, slot: usize) void {
    _ = slot;
    const rc: *ReverifyCtx = @ptrCast(@alignCast(ctx));
    if (isHit(rc.hits, index)) return;
    if (rc.results[index].status != .survived) return;
    if (!test_selection.needsConfiguredReverification(rc.jobs[index].commands, rc.cfg_test_commands)) return;
    rc.out[index] = rc.mutant_executor.runSpecs(rc.jobs[index].candidate, rc.jobs[index].source, rc.reverify_specs, rc.cfg_test_commands, rc.mode);
}

/// Shared state for the parallel mode matrix. Each worker handles one mutant
/// across every NON-primary mode in a single reused workspace, writing its
/// per-mode statuses into the disjoint `out[index*np ..][0..np]` window.
const ModeMatrixCtx = struct {
    jobs: []const Job,
    non_primary: []const report.Mode,
    reverify_specs: []const command.Spec,
    cfg_test_commands: []const []const u8,
    mutant_executor: MutantRunner,
    out: []report.ResultStatus,
    np: usize,
};

/// Worker-pool task: run one mutant's non-primary modes (with per-mode configured
/// reverification when the selection narrowed) in a single materialized workspace.
fn modeMatrixOneMutant(ctx: *anyopaque, index: usize, slot: usize) void {
    _ = slot;
    const mm: *ModeMatrixCtx = @ptrCast(@alignCast(ctx));
    const job = mm.jobs[index];
    const needs_reverify = test_selection.needsConfiguredReverification(job.commands, mm.cfg_test_commands);
    const slot_out = mm.out[index * mm.np ..][0..mm.np];
    mm.mutant_executor.runModes(
        job.candidate,
        job.source,
        job.command_specs,
        job.commands,
        if (needs_reverify) mm.reverify_specs else &.{},
        if (needs_reverify) mm.cfg_test_commands else &.{},
        mm.non_primary,
        slot_out,
    );
}

/// Index of `m` within `modes`; 0 if absent (callers only query members).
fn modeIndex(modes: []const report.Mode, m: report.Mode) usize {
    for (modes, 0..) |x, i| if (x == m) return i;
    return 0;
}

/// Normalize the configured `run.jobs` (validated `>= 1` by the config parser)
/// into a worker count. `--jobs` overrides this when set.
fn jobsFromConfig(run_jobs: i64) usize {
    if (run_jobs < 1) return 1;
    return @intCast(run_jobs);
}

pub const RunOutcome = struct {
    exit_code: u8,
    report: report.Report,
    /// Deterministic cache metadata for the run (the `cache.json` artifact). The
    /// report's `diagnostics.cache` is derived from this same metadata via
    /// `cacheDiagnostics`, so the two stay consistent (enabled/mode/hits match;
    /// the report adds `misses`).
    cache: cache.Metadata,
};

pub const RunError = error{
    OutputOutsideRoot,
    BackendParseError,
    InvalidCandidate,
    InvalidCommand,
    SourceFileMissing,
} || std.mem.Allocator.Error;

pub const ParseError = error{ MissingValue, UnknownOption, UnknownOperator, InvalidReportFormat, InvalidJobs, InvalidMode, BackendNotInRun, ConflictingOptions, DuplicateOption };

/// Tracks value-taking options seen during a single `parseArgs` pass so a
/// repeated scalar flag (`--jobs 2 --jobs 4`, `--config a --config b`) is
/// rejected as `DuplicateOption` instead of silently letting the last value win.
/// Boolean/idempotent flags (`--quiet`, `--verbose`, `--no-color`) are excluded:
/// repeating them is harmless and erroring would be user-hostile. This honours
/// the `ZNTL_CLI_INVALID_OPTION` contract in docs/ERROR_CODES.md, which covers
/// duplicated options.
const SeenScalars = struct {
    operator: bool = false,
    mutant: bool = false,
    report: bool = false,
    output: bool = false,
    jobs: bool = false,
    mode: bool = false,
    diff: bool = false,
    scope_files: bool = false,
};

/// Pure parser for Phase 1 `run` options (the argv following the `run` command).
/// Only documented options are accepted; anything else is a usage error so the
/// adapter can reject it instead of silently ignoring it.
pub fn parseArgs(args: []const []const u8) ParseError!Options {
    var opts: Options = .{};
    var seen: SeenScalars = .{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--fail-on-survivors")) {
            opts.fail_on_survivors = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, arg, "--quiet")) {
            opts.quiet = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            opts.no_cache = true;
        } else if (std.mem.eql(u8, arg, "--operator")) {
            if (seen.operator) return error.DuplicateOption;
            seen.operator = true;
            i += 1;
            if (i >= args.len) return error.MissingValue;
            // Reject an unknown operator up front; otherwise the filter matches no
            // candidate and the run reports 0 mutants with a clean exit 0, masking a
            // mistyped name in CI.
            if (!config.isKnownOperator(args[i])) return error.UnknownOperator;
            opts.operator_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--mutant")) {
            if (seen.mutant) return error.DuplicateOption;
            seen.mutant = true;
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.mutant_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--report")) {
            if (seen.report) return error.DuplicateOption;
            seen.report = true;
            i += 1;
            if (i >= args.len) return error.MissingValue;
            if (std.mem.eql(u8, args[i], "text")) {
                opts.report_format = .text;
            } else if (std.mem.eql(u8, args[i], "json")) {
                opts.report_format = .json;
            } else if (std.mem.eql(u8, args[i], "jsonl")) {
                opts.report_format = .jsonl;
            } else if (std.mem.eql(u8, args[i], "junit")) {
                opts.report_format = .junit;
            } else {
                return error.InvalidReportFormat;
            }
        } else if (std.mem.eql(u8, arg, "--output")) {
            if (seen.output) return error.DuplicateOption;
            seen.output = true;
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.output = args[i];
        } else if (std.mem.eql(u8, arg, "--jobs")) {
            if (seen.jobs) return error.DuplicateOption;
            seen.jobs = true;
            i += 1;
            if (i >= args.len) return error.MissingValue;
            const n = std.fmt.parseInt(usize, args[i], 10) catch return error.InvalidJobs;
            if (n < 1) return error.InvalidJobs; // worker count must be a positive integer
            opts.jobs = n;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            if (seen.mode) return error.DuplicateOption;
            seen.mode = true;
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.mode_override = safety_modes.parse(args[i]) orelse return error.InvalidMode;
        } else if (std.mem.eql(u8, arg, "--changed-only")) {
            opts.changed_only = true;
        } else if (std.mem.eql(u8, arg, "--diff")) {
            if (seen.diff) return error.DuplicateOption;
            seen.diff = true;
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.diff_base = args[i];
        } else if (std.mem.eql(u8, arg, "--scope-files")) {
            if (seen.scope_files) return error.DuplicateOption;
            seen.scope_files = true;
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.scope_files_csv = args[i];
        } else if (std.mem.eql(u8, arg, "--backend")) {
            // The experimental ZIR/AIR backends re-tag the AST candidate set and
            // are reachable only from `list-mutants`; `run` always uses the stable
            // AST backend, so `run --backend` is an explicit usage error rather
            // than a silently ignored no-op.
            return error.BackendNotInRun;
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            // Accepted for CLI uniformity (root.zig and doctest accept it too),
            // but a pure no-op here: run report renderers never emit ANSI color,
            // so there is nothing to suppress and nothing to store. Rejecting it
            // would make `--no-color` inconsistent across subcommands.
        } else {
            return error.UnknownOption;
        }
    }
    // --verbose and --quiet select opposite verbosities; accepting both would let
    // quiet silently win and discard the requested verbose output.
    if (opts.verbose and opts.quiet) return error.ConflictingOptions;
    // --changed-only/--diff/--scope-files are three ways to derive ONE scope set;
    // combining them is ambiguous (which base or list wins?), so reject rather than
    // silently pick one.
    var scope_inputs: u8 = 0;
    if (opts.changed_only) scope_inputs += 1;
    if (opts.diff_base != null) scope_inputs += 1;
    if (opts.scope_files_csv != null) scope_inputs += 1;
    if (scope_inputs > 1) return error.ConflictingOptions;
    return opts;
}

/// Run the Phase 1 flow and produce a deterministic report plus a process exit
/// code (0 ok, 1 survivors under --fail-on-survivors, 3 baseline failure).
pub fn run(
    arena: std.mem.Allocator,
    cfg: config.Config,
    files: []const FileSource,
    options: Options,
    baseline_executor: runner.Executor,
    mutant_executor: MutantRunner,
    obs: Observation,
) RunError!RunOutcome {
    if (options.output) |out| {
        if (config.isOutsideRoot(out)) return error.OutputOutsideRoot;
    }

    // `cache.enabled = false` disables the result cache exactly like `--no-cache`,
    // so the config field is honored rather than parsed-and-ignored.
    const no_cache = options.no_cache or !cfg.cache_enabled;

    // Safety/optimization mode matrix. `mode` is the primary mode
    // reflected in `result.mode`; `matrix_modes` is the full set run for the
    // additive `result.mode_matrix` (just the override, or the configured modes).
    const mode = safety_modes.primaryMode(cfg.zig_modes, options.mode_override);
    const matrix_modes = try safety_modes.matrixModes(arena, cfg.zig_modes, options.mode_override);
    const multi_mode = matrix_modes.len > 1;

    // Baseline.
    const baseline = runner.runBaseline(arena, baseline_executor, cfg.test_commands, obs.project_root) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCommand => return error.InvalidCommand,
    };

    if (baseline.status != .passed) {
        const meta = buildCacheMetadata(&.{}, no_cache, obs.zig_cache_namespace, false, 0);
        return .{
            .exit_code = 3,
            .report = .{
                .run = baseRun(obs, .baseline_failed),
                .baseline = .{ .status = .failed, .commands = baseline.commands },
                .summary = .{},
                .mutants = &.{},
                .diagnostics = .{ .cache = cache.toReportDiagnostics(meta) },
            },
            .cache = meta,
        };
    }

    // Generate candidates over the discovered files, then filter. The single parse
    // per file also yields each file's same-file tests, reused by selection.
    const generated = try generateCandidates(arena, cfg, files, options);
    const candidates = generated.mutants;

    const strategy = strategyFromConfig(cfg.test_selection);

    // Phase A (serial): resolve per-file selection -- including the unmutated
    // generated-command preflight, which must run serially through the baseline
    // executor -- and assemble one deterministic job per mutant. Selection state
    // and the baseline executor are only touched here, never on a worker thread.
    var file_cache: std.ArrayList(FileSelection) = .empty;
    // The resolution + selection specs are a pure function of the file (and the
    // run-constant config), so memoize them per file instead of recomputing for
    // every mutant from the same source.
    var spec_cache: std.ArrayList(FileSpec) = .empty;
    var job_list: std.ArrayList(Job) = .empty;
    // Index sources by path ONCE so the per-mutant lookup below is O(1), not a
    // linear scan of `files` per candidate (O(M*F)).
    var source_index = try buildSourceIndex(arena, files);
    for (candidates) |candidate| {
        const source = source_index.get(candidate.file) orelse return error.SourceFileMissing;
        const fs = blk: {
            for (spec_cache.items) |c| {
                if (std.mem.eql(u8, c.file, candidate.file)) break :blk c;
            }
            const fsel = try selectionForFile(arena, &file_cache, strategy, candidate.file, &generated.same_file_tests, cfg.test_commands, baseline_executor, obs.project_root);
            const resolution = try test_selection.resolve(arena, strategy, candidate.file, fsel.same_file_tests, cfg.test_commands, fsel.preflight, fsel.generated_in_baseline);
            const specs = try commandSpecsForSelection(arena, resolution.commands, candidate.file);
            const computed = FileSpec{ .file = candidate.file, .resolution = resolution, .specs = specs };
            try spec_cache.append(arena, computed);
            break :blk computed;
        };
        try job_list.append(arena, .{ .candidate = candidate, .source = source, .commands = fs.resolution.commands, .command_specs = fs.specs, .selection = fs.resolution.selection });
    }
    const jobs = try job_list.toOwnedSlice(arena);

    // Result-cache inputs. The key is a pure function of the mutant + sources +
    // commands + mode, so the per-file project/source hashes and the per-job keys
    // are computed ONCE here and reused for reuse-lookup (below), persistence
    // (after Phase B.5), and the Phase C metadata emit -- the looked-up and stored
    // keys are therefore guaranteed identical.
    const project_hash = try projectHash(arena, files);
    const source_hashes = try buildSourceHashIndex(arena, files);
    // Keys are computed whenever the cache is enabled (single- AND multi-mode) so
    // the metadata artifact is unchanged. `job_keys[i]` is null only when caching
    // is disabled (`--no-cache`/`cache.enabled=false`).
    const job_keys = try arena.alloc(?[]const u8, jobs.len);
    for (jobs, 0..) |job, ji| {
        job_keys[ji] = if (no_cache) null else try cacheKeyForJob(
            arena,
            job,
            obs,
            cfg.test_commands,
            source_hashes.get(job.candidate.file) orelse return error.SourceFileMissing,
            project_hash,
            mode,
        );
    }

    const results = try arena.alloc(mutant_runner.MutationResult, jobs.len);

    // Read-side result reuse (docs/PERFORMANCE_STRATEGY.md). Only attempted with a
    // wired store, an enabled cache, and a SINGLE-mode run: the key encodes only
    // the primary mode, so a stored single-mode `MutationResult` fully determines
    // that mutant's report contribution (its `mode_matrix` is null). A multi-mode
    // run's per-mutant report also depends on the non-primary modes the key does
    // not capture, so reuse is conservatively disabled there (every mutant a miss,
    // exactly as before). Each served entry is a POST-REVERIFY terminal verdict, so
    // a hit fills `results[i]` directly and skips both Phase B and Phase B.5 for
    // that mutant. SOUNDNESS: the configured-suite reverify remains the survivor
    // authority -- it is what was stored -- and an unreadable/stale/non-terminal
    // entry deserializes to null and is treated as a miss, never served.
    const hits = try arena.alloc(bool, jobs.len);
    @memset(hits, false);
    var hit_count: u64 = 0;
    const reuse_enabled = options.result_cache != null and !no_cache and !multi_mode;
    if (reuse_enabled) {
        const store = options.result_cache.?;
        for (job_keys, 0..) |maybe_key, ji| {
            const key = maybe_key orelse continue;
            const bytes = store.get(key) orelse continue;
            const served = deserializeCachedResult(arena, bytes, mode) orelse continue;
            results[ji] = served;
            hits[ji] = true;
            hit_count += 1;
        }
    }

    // Phase B (parallel): run each NON-hit mutant through the injected runner
    // across at most `--jobs` (overriding `run.jobs`) workers. Results are
    // collected by index, so the worker count changes only concurrency -- never
    // which result belongs to which mutant. jobs == 1 runs inline (conservative
    // default). The injected runner's allocator must be thread-safe under
    // --jobs > 1: the adapter wraps the process arena in worker_pool.LockedAllocator
    // (the arena is not thread-safe). Each worker writes a disjoint results slot.
    const requested_jobs: usize = if (options.jobs) |j| j else jobsFromConfig(cfg.run_jobs);
    var pctx = ParallelCtx{ .jobs = jobs, .results = results, .mutant_executor = mutant_executor, .mode = mode, .hits = hits, .progress = options.progress };
    worker_pool.run(requested_jobs, jobs.len, &pctx, runOneMutant);

    // Phase B.5 (serial): re-verify narrowed-selection survivors against the full
    // configured command set. A same-file/impact selection may run a command
    // weaker than the configured suite (docs/TEST_SELECTION.md), so a `survived`
    // verdict from a narrowed selection is unsound until the configured suite is
    // confirmed to also miss the mutant. Only survivors pay this cost, and only
    // when the selection actually narrowed; the configured re-verification
    // commands are appended to the mutant's evidence so the recorded
    // `survived`/`killed` verdict always reflects the configured suite (I-012:
    // nothing is hidden). The primary mode is re-verified here before the mode
    // matrix reads it.
    // `cfg.test_commands` is constant for the whole run, so parse it into specs
    // ONCE and share the read-only slice across every surviving mutant rather than
    // re-parsing per survivor.
    const reverify_specs = try commandSpecsForConfigured(arena, cfg.test_commands);
    // Phase B.5 (parallel): the subprocess reverification dominates wall time, so
    // run each narrowed survivor's configured suite across the worker pool, then
    // merge serially -- the merge touches the non-thread-safe arena, the runs do
    // not. Disjoint `reverify_out` slots, so no synchronization is needed.
    const reverify_out = try arena.alloc(?mutant_runner.MutationResult, jobs.len);
    @memset(reverify_out, null);
    var rvctx = ReverifyCtx{
        .jobs = jobs,
        .results = results,
        .out = reverify_out,
        .reverify_specs = reverify_specs,
        .cfg_test_commands = cfg.test_commands,
        .mutant_executor = mutant_executor,
        .mode = mode,
        .hits = hits,
    };
    worker_pool.run(requested_jobs, jobs.len, &rvctx, reverifyOneMutant);
    for (reverify_out, 0..) |maybe, ji| {
        if (maybe) |reverify| results[ji] = try mergeReverification(arena, results[ji], reverify);
    }

    // Persist the POST-REVERIFY verdicts (write side of reuse). Only when reuse is
    // enabled (wired store, enabled cache, single-mode); only freshly computed
    // misses (a hit is already the stored value); and only terminal verdicts
    // (`cacheableOutcome` excludes timeout/crash/invalid/skip, which can differ
    // between runs and must never be served). `results[ji]` here is authoritative:
    // it already reflects any configured-suite reverification merged above.
    if (reuse_enabled) {
        const store = options.result_cache.?;
        for (job_keys, 0..) |maybe_key, ji| {
            if (hits[ji]) continue;
            const key = maybe_key orelse continue;
            if (!cacheableOutcome(results[ji].status)) continue;
            store.put(key, try serializeCachedResult(arena, results[ji]));
        }
    }

    // Mode matrix: when more than one mode is run, record each mode's per-mutant
    // status. The primary mode reuses the Phase B results (no re-run). The
    // non-primary modes run in parallel OVER MUTANTS, each mutant
    // materializing a single workspace reused across its modes.
    // `mode_grid[mode_index][job_index]` holds the status.
    var mode_grid: [][]report.ResultStatus = &.{};
    if (multi_mode) {
        var np_list: std.ArrayList(report.Mode) = .empty;
        for (matrix_modes) |m| {
            if (m != mode) try np_list.append(arena, m);
        }
        const non_primary = try np_list.toOwnedSlice(arena);
        const np = non_primary.len;

        // Disjoint per-mutant output window (row-major by job), preallocated so the
        // parallel tasks never allocate from the arena.
        const mm_out = try arena.alloc(report.ResultStatus, jobs.len * np);
        var mmctx = ModeMatrixCtx{
            .jobs = jobs,
            .non_primary = non_primary,
            .reverify_specs = reverify_specs,
            .cfg_test_commands = cfg.test_commands,
            .mutant_executor = mutant_executor,
            .out = mm_out,
            .np = np,
        };
        if (np > 0) worker_pool.run(requested_jobs, jobs.len, &mmctx, modeMatrixOneMutant);

        // Assemble the grid serially: primary column from Phase B results, each
        // non-primary column scattered from the per-mutant windows.
        const grid = try arena.alloc([]report.ResultStatus, matrix_modes.len);
        for (matrix_modes, 0..) |m, mi| {
            const col = try arena.alloc(report.ResultStatus, jobs.len);
            if (m == mode) {
                for (results, 0..) |r, ji| col[ji] = r.status;
            } else {
                const k = modeIndex(non_primary, m);
                for (0..jobs.len) |ji| col[ji] = mm_out[ji * np + k];
            }
            grid[mi] = col;
        }
        mode_grid = grid;
    }

    // Phase C (serial): build report entries and result-cache keys in mutant
    // order, then sort into canonical report order. Because the report is sorted
    // here, serial and parallel runs produce equivalent reports.
    var entries: std.ArrayList(report.Mutant) = .empty;
    var result_keys: std.ArrayList(cache.ResultKey) = .empty;
    for (jobs, results, job_keys, 0..) |job, result, maybe_key, ji| {
        const mode_matrix: ?[]const report.ModeResult = if (multi_mode) blk: {
            const rows = try arena.alloc(report.ModeResult, matrix_modes.len);
            for (matrix_modes, 0..) |m, mi| rows[mi] = .{ .mode = m, .status = mode_grid[mi][ji] };
            safety_modes.sortModeResults(rows);
            break :blk rows;
        } else null;
        try entries.append(arena, try buildEntry(arena, job.candidate, job.source, result, mode, mode_matrix, job.selection));

        // Emit the precomputed result-cache key into the metadata. A disabled cache
        // has no key (`job_keys[ji] == null`). Only deterministic outcomes get a
        // key: a timeout / compiler_crash / invalid result is transient (host load,
        // an FS race, a flaky compiler) and shares a byte-identical key with a clean
        // run of the same mutant, so emitting one would let a future reuse pass
        // serve that transient verdict as a real hit, hiding a kill or survivor.
        // (A hit's verdict was itself terminal when stored, so served hits are
        // always cacheable and appear here too -- `hits <= result_keys.len`.)
        if (maybe_key) |key| {
            if (cacheableOutcome(result.status)) {
                try result_keys.append(arena, .{ .mutant_id = job.candidate.id, .key = key });
            }
        }
    }
    const mutants = try entries.toOwnedSlice(arena);
    report.sortAndAssignDisplayIds(mutants);
    const summary = report.summarize(mutants);

    var exit_code: u8 = 0;
    if (options.fail_on_survivors and summary.survived > 0) exit_code = 1;

    const cache_meta = buildCacheMetadata(try result_keys.toOwnedSlice(arena), no_cache, obs.zig_cache_namespace, reuse_enabled, hit_count);
    return .{
        .exit_code = exit_code,
        .report = .{
            .run = baseRun(obs, .completed),
            .baseline = .{ .status = .passed, .commands = baseline.commands },
            .summary = summary,
            .mutants = mutants,
            .diagnostics = .{ .cache = cache.toReportDiagnostics(cache_meta) },
        },
        .cache = cache_meta,
    };
}

/// Whether a mutant's outcome is deterministic enough to key a reusable cache
/// entry. Transient outcomes (a timeout, a compiler crash, an invalid-workspace
/// failure, or a skip) can differ between two runs of the same mutant, so they
/// must never be stored under the run-invariant key.
fn cacheableOutcome(status: report.ResultStatus) bool {
    return switch (status) {
        .killed, .survived, .compile_error => true,
        .compiler_crash, .timeout, .skipped, .invalid => false,
    };
}

/// On-disk schema tag for a persisted result entry. Bumped independently of the
/// key namespace so an incompatible entry layout is rejected (treated as a miss)
/// even if a key were to collide across versions.
const cached_result_schema = "zentinel.result.v2";

/// A persisted, content-addressed result entry. It carries the FULL post-reverify
/// `MutationResult` (status, every command result with its evidence, the result
/// evidence, and the skip reason) so a served entry reconstructs a byte-identical
/// report through `buildEntry` -- report-equivalence, not just the verdict tag.
/// `mutant_id` is recorded for cross-checking but the report's identity always
/// comes from the freshly generated candidate, never from the cache.
const CachedResult = struct {
    schema_version: []const u8 = cached_result_schema,
    status: report.ResultStatus,
    mode: report.Mode,
    classifier_source: mutant_runner.ClassifierSource,
    mutant_id: []const u8,
    commands: []const report.CommandResult,
    evidence: report.Evidence,
    skip_reason: ?[]const u8,
};

/// Serialize a post-reverify `MutationResult` into a persistable result entry.
fn serializeCachedResult(arena: std.mem.Allocator, result: mutant_runner.MutationResult) std.mem.Allocator.Error![]u8 {
    const entry = CachedResult{
        .status = result.status,
        .mode = result.mode,
        .classifier_source = result.classifier_source,
        .mutant_id = result.mutant_id,
        .commands = result.commands,
        .evidence = result.evidence,
        .skip_reason = result.skip_reason,
    };
    return std.json.Stringify.valueAlloc(arena, entry, .{});
}

/// Reconstruct a `MutationResult` from a persisted entry, or null when the bytes
/// are unreadable, carry an unexpected schema, or hold a non-terminal verdict.
/// Any of those is treated as a miss: a corrupt or stale entry can never be served
/// as a verdict. `mode` is the run's primary mode; an entry whose recorded mode
/// disagrees is rejected (the key encodes the primary mode, so this is a
/// belt-and-braces guard against a hand-edited or stale store).
fn deserializeCachedResult(arena: std.mem.Allocator, bytes: []const u8, mode: report.Mode) ?mutant_runner.MutationResult {
    const entry = std.json.parseFromSliceLeaky(CachedResult, arena, bytes, .{}) catch return null;
    if (!std.mem.eql(u8, entry.schema_version, cached_result_schema)) return null;
    if (entry.mode != mode) return null;
    if (!cacheableOutcome(entry.status)) return null;
    return .{
        .mutant_id = entry.mutant_id,
        .status = entry.status,
        .mode = entry.mode,
        .classifier_source = entry.classifier_source,
        .commands = entry.commands,
        .evidence = entry.evidence,
        .skip_reason = entry.skip_reason,
    };
}

fn baseRun(obs: Observation, status: report.RunStatus) report.Run {
    return .{
        .id = obs.run_id,
        .status = status,
        .@"error" = null,
        .zentinel_version = obs.zentinel_version,
        .zig_version = obs.zig_version,
        .command = "zentinel run",
        .config_hash = obs.config_hash,
        .project_root = obs.project_root,
        .started_at = obs.started_at,
        .duration_ms = obs.duration_ms,
    };
}

/// Test-only counter: how many times the per-run source index (path -> bytes) is
/// built. Every file is indexed ONCE so the Phase A per-mutant source lookup is
/// O(1) (`index.get`), not a linear scan of `files` per candidate (O(M*F)); a
/// regression that rebuilt or scanned per mutant would push this above 1. Stored
/// as an atomic so a regression that incremented it from a worker thread could
/// not data-race this shared global (load/store via `.monotonic`).
pub var source_index_builds: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

/// Index source bytes by project-relative path. First occurrence wins, matching
/// the prior `sourceFor` linear scan's first-match semantics (`files` is already
/// de-duplicated by `discover`, so this only matters defensively).
fn buildSourceIndex(arena: std.mem.Allocator, files: []const FileSource) std.mem.Allocator.Error!std.StringHashMap([]const u8) {
    _ = source_index_builds.fetchAdd(1, .monotonic);
    var index = std.StringHashMap([]const u8).init(arena);
    for (files) |f| {
        const gop = try index.getOrPut(f.path);
        if (!gop.found_existing) gop.value_ptr.* = f.source;
    }
    return index;
}

/// Test-only counter: how many times a source file's SHA-256 result-cache hash is
/// computed. The hash is a pure function of the file bytes, identical for every
/// mutant from that file, so it is computed ONCE per unique file and reused in the
/// Phase C per-mutant loop; recomputing per mutant would push this to O(M). Stored
/// as an atomic so a regression that incremented it from a worker thread could not
/// data-race this shared global (load/store via `.monotonic`).
pub var source_hash_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

/// Index each unique file's source-cache hash (path -> hex SHA-256) ONCE, so the
/// Phase C result-cache key lookup is O(1) per mutant instead of an O(M) re-hash of
/// the same bytes. First occurrence wins, mirroring buildSourceIndex.
fn buildSourceHashIndex(arena: std.mem.Allocator, files: []const FileSource) std.mem.Allocator.Error!std.StringHashMap([]const u8) {
    var index = std.StringHashMap([]const u8).init(arena);
    for (files) |f| {
        const gop = try index.getOrPut(f.path);
        if (!gop.found_existing) {
            _ = source_hash_count.fetchAdd(1, .monotonic);
            gop.value_ptr.* = try cache.sourceHash(arena, f.source);
        }
    }
    return index;
}

/// Return the first project-relative source file that fails AST parsing.
/// Adapters use this after `BackendParseError` to report a concrete file while
/// the core error set remains compact and deterministic.
pub fn firstBackendParseError(arena: std.mem.Allocator, files: []const FileSource) std.mem.Allocator.Error!?[]const u8 {
    for (files) |f| {
        var parsed = try ast_backend.parse(arena, f.path, f.source);
        defer parsed.deinit();
        if (!parsed.ok()) return f.path;
    }
    return null;
}

/// Assemble run cache metadata. `--no-cache` disables the result cache (no result
/// keys, mode disabled) but leaves the Zig build-cache isolation metadata intact
/// (docs/PERFORMANCE_STRATEGY.md). `reuse` is true only when a result store was
/// wired and consulted (single-mode, enabled cache): then the mode is `read_write`
/// and `hits` counts the served verdicts. With the cache enabled but no store
/// wired, `reuse` is false, so the mode stays `metadata_only` and `hits` is 0 --
/// byte-identical to the prior metadata-only behavior.
fn buildCacheMetadata(result_keys: []const cache.ResultKey, no_cache: bool, namespace: []const u8, reuse: bool, hits: u64) cache.Metadata {
    return .{
        .enabled = !no_cache,
        .mode = if (no_cache) .disabled else if (reuse) .read_write else .metadata_only,
        .result_keys = if (no_cache) &.{} else result_keys,
        .build_cache = .{ .namespace = namespace, .isolated = true },
        .hits = if (no_cache) 0 else hits,
    };
}

/// Compute the deterministic result-cache key for one job. Pure: a function of the
/// mutant identity, the source/project/config hashes, the executed and configured
/// commands, the primary mode, and the environment -- never the run's outcome. The
/// same key drives both pre-run reuse lookup and post-run persistence, so it is
/// computed ONCE per job (in Phase A) and shared with the Phase C metadata emit,
/// guaranteeing the looked-up and stored keys are identical.
fn cacheKeyForJob(
    arena: std.mem.Allocator,
    job: Job,
    obs: Observation,
    cfg_test_commands: []const []const u8,
    source_hash: []const u8,
    project_hash: []const u8,
    mode: report.Mode,
) std.mem.Allocator.Error![]const u8 {
    return cache.computeKey(arena, .{
        .mutant_id = job.candidate.id,
        .zentinel_version = obs.zentinel_version,
        .zig_version = obs.zig_version,
        .zig_cache_namespace = obs.zig_cache_namespace,
        .backend = @tagName(job.candidate.backend),
        .backend_version = job.candidate.backend_version,
        .operator = job.candidate.operator,
        .source_hash = source_hash,
        .project_hash = project_hash,
        .config_hash = obs.config_hash,
        .test_command = try joinCommands(arena, job.commands),
        .configured_command = try joinCommands(arena, cfg_test_commands),
        .mode = @tagName(mode),
        .environment = "minimal",
        .environment_hash = obs.environment_hash,
    });
}

/// Encode a command vector into one canonical, INJECTIVE cache-key field. Each
/// command is length-prefixed (and the vector is count-prefixed), so two distinct
/// vectors can never collide into the same field -- e.g. `["a && b"]` and
/// `["a", "b"]` produced the identical string under the prior `" && "` join,
/// which would let one cached verdict be reused for the other.
pub fn joinCommands(arena: std.mem.Allocator, commands: []const []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}\n", .{commands.len}));
    for (commands) |c| {
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}\n", .{c.len}));
        try out.appendSlice(arena, c);
        try out.append(arena, '\n');
    }
    return out.toOwnedSlice(arena);
}

fn fileSourceLess(_: void, a: FileSource, b: FileSource) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

fn projectHash(arena: std.mem.Allocator, files: []const FileSource) std.mem.Allocator.Error![]const u8 {
    const sorted = try arena.dupe(FileSource, files);
    std.mem.sort(FileSource, sorted, {}, fileSourceLess);

    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update("zentinel.project-sources.v1\n");
    for (sorted) |f| {
        h.update(f.path);
        h.update("\n");
        h.update(f.source);
        h.update("\n");
    }
    var digest: [32]u8 = undefined;
    h.final(&digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return arena.dupe(u8, &hex);
}

fn strategyFromConfig(s: []const u8) test_selection.Strategy {
    if (std.mem.eql(u8, s, "same_file")) return .same_file;
    if (std.mem.eql(u8, s, "same_file_then_package")) return .same_file_then_package;
    if (std.mem.eql(u8, s, "impact_graph")) return .impact_graph;
    // `all` and `package` both run the configured commands directly; the report
    // has no narrower `package` strategy variant, so it is reported as `all`.
    return .all;
}

/// Per-file selection inputs: the discovered same-file tests, the (already-run)
/// generated-command preflight result, and whether the generated command was
/// already a baseline command (so it needs no preflight).
const FileSelection = struct {
    file: []const u8,
    same_file_tests: []const report.SelectedTest,
    preflight: ?report.CommandResult,
    generated_in_baseline: bool,
};

/// Per-file memo of the resolved selection and its parsed command specs, shared
/// by every mutant from that file. All fields are arena-owned, read-only.
const FileSpec = struct {
    file: []const u8,
    resolution: test_selection.Resolution,
    specs: []const command.Spec,
};

/// Test-only counter: how many times the configured commands were parsed into
/// specs. They are constant across the Phase B.5 survivor reverification loop, so
/// this must be 1 per run, not 1 per surviving mutant.
pub var configured_specs_parse_count: usize = 0;

fn commandSpecsForConfigured(arena: std.mem.Allocator, commands: []const []const u8) std.mem.Allocator.Error![]const command.Spec {
    configured_specs_parse_count += 1;
    const specs = try arena.alloc(command.Spec, commands.len);
    for (commands, 0..) |original, i| {
        const argv = switch (try command.parse(arena, original)) {
            .ok => |a| a,
            // Configured commands are validated by `check`; preserve the old
            // fail-closed runner behavior by passing an argv that will not be
            // mistaken for a generated structured command.
            .invalid => try arena.dupe([]const u8, &.{original}),
        };
        specs[i] = .{ .original = original, .argv = argv };
    }
    return specs;
}

/// Test-only counter: how many times the per-file selection specs were built.
/// The selection commands are identical for every mutant from the same source
/// file, so this must be 1 per unique file, not 1 per mutant.
pub var selection_specs_build_count: usize = 0;

fn commandSpecsForSelection(arena: std.mem.Allocator, commands: []const []const u8, file: []const u8) std.mem.Allocator.Error![]const command.Spec {
    selection_specs_build_count += 1;
    const generated = try test_selection.generatedCommand(arena, file);
    const generated_argv = try test_selection.generatedCommandArgv(arena, file);
    const specs = try arena.alloc(command.Spec, commands.len);
    for (commands, 0..) |original, i| {
        if (std.mem.eql(u8, original, generated)) {
            specs[i] = .{ .original = original, .argv = generated_argv };
        } else {
            const parsed = switch (try command.parse(arena, original)) {
                .ok => |a| a,
                .invalid => try arena.dupe([]const u8, &.{original}),
            };
            specs[i] = .{ .original = original, .argv = parsed };
        }
    }
    return specs;
}

/// Test-only counter: how many times a source file's AST is parsed during a run.
/// Each file is parsed once in `generateCandidates`; the same-file selection then
/// reuses that parse via the per-file table rather than parsing a second time, so
/// this must be 1 per unique file, not 2.
pub var ast_parse_count: usize = 0;

/// Compute (and cache) the selection inputs for `file`. When the strategy uses
/// same-file tests and the generated `zig test <file>` command is not already a
/// baseline command, this runs the generated command against the UNMUTATED
/// project through the baseline executor and records the preflight evidence, so
/// a generated command must pass an unmutated preflight before it classifies a
/// mutant (docs/TEST_SELECTION.md).
fn selectionForFile(
    arena: std.mem.Allocator,
    sel_cache: *std.ArrayList(FileSelection),
    strategy: test_selection.Strategy,
    file: []const u8,
    same_file_tests_by_file: *const std.StringHashMap([]const report.SelectedTest),
    configured: []const []const u8,
    baseline_executor: runner.Executor,
    cwd: []const u8,
) std.mem.Allocator.Error!FileSelection {
    for (sel_cache.items) |c| {
        if (std.mem.eql(u8, c.file, file)) return c;
    }

    var same_file_tests: []const report.SelectedTest = &.{};
    const same_file_enabled = strategy == .same_file or strategy == .same_file_then_package or strategy == .impact_graph;
    if (same_file_enabled) {
        // Reuse the parse from generateCandidates: this file's same-file tests were
        // computed there and memoized, so selection never re-parses the file.
        same_file_tests = same_file_tests_by_file.get(file) orelse &.{};
    }

    const generated = try test_selection.generatedCommand(arena, file);
    const generated_in_baseline = contains(configured, generated);

    var preflight: ?report.CommandResult = null;
    if (same_file_enabled and same_file_tests.len > 0 and !generated_in_baseline) {
        preflight = try runPreflight(arena, baseline_executor, generated, try test_selection.generatedCommandArgv(arena, file), cwd);
    }

    const sel = FileSelection{
        .file = file,
        .same_file_tests = same_file_tests,
        .preflight = preflight,
        .generated_in_baseline = generated_in_baseline,
    };
    try sel_cache.append(arena, sel);
    return sel;
}

fn contains(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

/// Run the generated selected command against the unmutated project and classify
/// it as a `selection_preflight` command result.
fn runPreflight(arena: std.mem.Allocator, executor: runner.Executor, original: []const u8, argv: []const []const u8, cwd: []const u8) std.mem.Allocator.Error!?report.CommandResult {
    const raw = executor.run(argv);
    return try runner.classifyCommand(arena, .selection_preflight, original, argv, cwd, raw);
}

/// Test-only counter: how many times the enabled-operator membership set is
/// built (a single linear pass over cfg.mutators_enabled) during candidate
/// generation. The enabled set is constant for a run, so this must be 1 per run,
/// not 1 per raw candidate -- the prior `enabled()` helper re-scanned the list
/// for every candidate, an O(M*E) filter.
pub var enabled_operator_scan_count: usize = 0;

/// Build the enabled-operator membership set with one linear pass over
/// cfg.mutators_enabled, so the per-candidate enable check is an O(1) hash lookup
/// rather than an O(E) scan repeated for every raw candidate (O(M*E)).
fn enabledOperatorSet(arena: std.mem.Allocator, cfg: config.Config) std.mem.Allocator.Error!std.StringHashMap(void) {
    enabled_operator_scan_count += 1;
    var set = std.StringHashMap(void).init(arena);
    for (cfg.mutators_enabled) |op| try set.put(op, {});
    return set;
}

/// The mutant candidates plus the same-file tests discovered during the single
/// per-file parse, so the same-file selection never re-parses a file.
const GeneratedCandidates = struct {
    mutants: []mutant.Mutant,
    same_file_tests: std.StringHashMap([]const report.SelectedTest),
};

/// Recognize Phase 1+2 AST candidates over every file (keeping only those whose
/// operator is enabled in config and that match the optional CLI filters) and, from
/// the same parse, record each file's same-file tests so selection need not
/// re-parse the file.
fn generateCandidates(arena: std.mem.Allocator, cfg: config.Config, files: []const FileSource, options: Options) RunError!GeneratedCandidates {
    var collector = ast_backend.Collector.init(arena);
    var same_file_tests = std.StringHashMap([]const report.SelectedTest).init(arena);
    for (files) |f| {
        ast_parse_count += 1;
        var parsed = try ast_backend.parse(arena, f.path, f.source);
        defer parsed.deinit();
        if (!parsed.ok()) return error.BackendParseError;
        const test_ranges = try ast_backend.testDeclRanges(parsed, arena);
        // Discover same-file tests from THIS parse so selectionForFile reuses them
        // instead of parsing the file a second time.
        try same_file_tests.put(f.path, try test_selection.sameFileTests(arena, parsed, f.path));
        try arithmetic.collect(&collector, parsed, f.path, test_ranges);
        try comparison.collect(&collector, parsed, f.path, test_ranges);
        try logical.collect(&collector, parsed, f.path, test_ranges);
        try boolean.collect(&collector, parsed, f.path, test_ranges);
        // Phase-2 stable collectors: without these the optional,
        // error-path, integer-boundary, and loop-boundary operators load in config
        // but never emit a mutant, silently under-reporting coverage.
        try optional.collect(&collector, parsed, f.path, test_ranges);
        try error_path.collect(&collector, parsed, f.path, test_ranges);
        try integer_boundary.collect(&collector, parsed, f.path, test_ranges);
        try loop_boundary.collect(&collector, parsed, f.path, test_ranges);
    }
    if (collector.invalidCount() > 0) return error.InvalidCandidate;
    const all = try collector.finishRaw();

    // Build the enabled-operator set once per run; each candidate's enable check
    // is then an O(1) lookup instead of an O(E) linear scan per candidate.
    const enabled_ops = try enabledOperatorSet(arena, cfg);
    // Optional diff-scope: restrict mutation to candidates whose file is in the
    // resolved set. Built once like `enabled_ops`. `files` was fully parsed above,
    // so `projectHash` and same-file selection are unaffected -- scoping only omits
    // out-of-scope mutants, mirroring `operator_filter`/`mutant_filter` below.
    const scope_set: ?std.StringHashMap(void) = if (options.scope_files) |paths| blk: {
        var set = std.StringHashMap(void).init(arena);
        for (paths) |p| try set.put(p, {});
        break :blk set;
    } else null;
    var kept: std.ArrayList(mutant.Mutant) = .empty;
    for (all) |c| {
        if (!enabled_ops.contains(c.operator)) continue;
        if (options.operator_filter) |op| {
            if (!std.mem.eql(u8, c.operator, op)) continue;
        }
        if (options.mutant_filter) |id| {
            if (!std.mem.eql(u8, c.id, id)) continue;
        }
        if (scope_set) |set| {
            if (!set.contains(c.file)) continue;
        }
        try kept.append(arena, c);
    }
    const mutants = try mutant.sortAndDedupe(arena, kept.items);
    return .{ .mutants = mutants, .same_file_tests = same_file_tests };
}

/// Merge a narrowed-selection survivor with its configured-suite re-verification.
/// The narrowed commands all passed (the mutant survived them), so the configured
/// suite is authoritative for the final verdict: its command results are appended
/// after the narrowed ones and its status replaces the survivor's. The combined
/// command list keeps every command at `phase = .mutant` (report invariant) and
/// records the full evidence chain that produced the recorded status, so a mutant
/// the configured suite kills is never left reported as `survived`.
fn mergeReverification(
    arena: std.mem.Allocator,
    narrowed: mutant_runner.MutationResult,
    reverify: mutant_runner.MutationResult,
) std.mem.Allocator.Error!mutant_runner.MutationResult {
    const commands = try arena.alloc(report.CommandResult, narrowed.commands.len + reverify.commands.len);
    @memcpy(commands[0..narrowed.commands.len], narrowed.commands);
    @memcpy(commands[narrowed.commands.len..], reverify.commands);
    return .{
        .mutant_id = narrowed.mutant_id,
        .status = reverify.status,
        .mode = narrowed.mode,
        .classifier_source = reverify.classifier_source,
        .commands = commands,
        .evidence = reverify.evidence,
        .skip_reason = reverify.skip_reason,
    };
}

fn buildEntry(
    arena: std.mem.Allocator,
    candidate: mutant.Mutant,
    source: []const u8,
    result: mutant_runner.MutationResult,
    mode: report.Mode,
    mode_matrix: ?[]const report.ModeResult,
    selection: report.TestSelection,
) std.mem.Allocator.Error!report.Mutant {
    var duration: u64 = 0;
    for (result.commands) |c| duration += c.duration_ms;

    return .{
        .id = candidate.id,
        .display_id = 1, // reassigned after sorting
        .backend = candidate.backend,
        .backend_stability = candidate.backend_stability,
        .operator = candidate.operator,
        .operator_stability = candidate.operator_stability,
        .file = candidate.file,
        .span = candidate.span,
        .original = candidate.original,
        .replacement = candidate.replacement,
        .diff = try computeDiff(arena, source, candidate),
        // SEM-1c (compile-as-classifier): the runner already compiled this mutant,
        // so report the compiler's ACTUAL verdict (from the terminal run status)
        // rather than the per-operator heuristic guess. Ambiguous outcomes
        // (timeout/crash/invalid/skipped) keep the heuristic. In a multi-mode matrix
        // run this reflects the PRIMARY (first configured) mode's status, matching
        // the rest of the top-level entry (`result.status`); per-mode compile
        // outcomes live in `mode_matrix`.
        .expected_compile = semantic_filter.empiricalExpectedCompile(candidate.expected_compile, result.status),
        .result = .{
            .status = result.status,
            .mode = mode,
            .commands = result.commands,
            .phase = .mutant,
            .duration_ms = duration,
            .evidence = result.evidence,
            .skip_reason = result.skip_reason,
            .mode_matrix = mode_matrix,
        },
        .test_selection = selection,
        .advisory = .{ .equivalent_risks = candidate.equivalent_risks, .ai = null },
    };
}

/// Line-level diff for one mutant: the original line and the patched line.
fn computeDiff(arena: std.mem.Allocator, source: []const u8, candidate: mutant.Mutant) std.mem.Allocator.Error![]const []const u8 {
    const start: usize = candidate.span.byte_start;
    const end: usize = candidate.span.byte_end;
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..start], '\n')) |i| i + 1 else 0;
    const line_end = if (std.mem.indexOfScalarPos(u8, source, end, '\n')) |i| i else source.len;
    const original_line = source[line_start..line_end];

    var patched: std.ArrayList(u8) = .empty;
    try patched.appendSlice(arena, source[line_start..start]);
    try patched.appendSlice(arena, candidate.replacement);
    try patched.appendSlice(arena, source[end..line_end]);

    const minus = try std.fmt.allocPrint(arena, "- {s}", .{original_line});
    const plus = try std.fmt.allocPrint(arena, "+ {s}", .{patched.items});
    return try arena.dupe([]const u8, &.{ minus, plus });
}
