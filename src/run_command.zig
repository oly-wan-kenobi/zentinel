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
const report = @import("report.zig");
const command = @import("command.zig");
const test_selection = @import("test_selection.zig");
const cache = @import("cache.zig");
const worker_pool = @import("worker_pool.zig");
const safety_modes = @import("safety_modes.zig");

pub const ReportFormat = enum { text, json, jsonl, junit };

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
    /// Worker count for parallel mutant execution (`--jobs <n>`). When set, it
    /// overrides normalized `run.jobs`. Chooses only concurrency, never report
    /// ordering or mutation semantics; `null` falls back to `run.jobs`.
    jobs: ?usize = null,
    /// Single-invocation safety/optimization mode override (`--mode <...>`,
    /// task 058). When set it replaces the configured `zig.modes` for this run and
    /// yields a single-mode report; `null` uses the configured modes.
    mode_override: ?report.Mode = null,
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

    pub fn run(self: MutantRunner, m: mutant.Mutant, source: []const u8, commands: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
        return self.runFn(self.ctx, m, source, commands, mode);
    }

    pub fn runSpecs(self: MutantRunner, m: mutant.Mutant, source: []const u8, specs: []const command.Spec, originals: []const []const u8, mode: report.Mode) mutant_runner.MutationResult {
        if (self.runSpecsFn) |f| return f(self.ctx, m, source, specs, mode);
        return self.runFn(self.ctx, m, source, originals, mode);
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
};

/// Worker-pool task: run one mutant and store its result at the matching index.
/// The injected runner isolates each mutant in its own content-addressed
/// workspace, so concurrent workers never share a workspace, cache, or output.
fn runOneMutant(ctx: *anyopaque, index: usize, slot: usize) void {
    _ = slot;
    const pc: *ParallelCtx = @ptrCast(@alignCast(ctx));
    const job = pc.jobs[index];
    pc.results[index] = pc.mutant_executor.runSpecs(job.candidate, job.source, job.command_specs, job.commands, pc.mode);
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
    /// Deterministic cache metadata for the run. Separate from the report's
    /// disabled-cache diagnostics: Phase 1 computes keys but never reuses results.
    cache: cache.Metadata,
};

pub const RunError = error{
    OutputOutsideRoot,
    BackendParseError,
    InvalidCandidate,
    InvalidCommand,
    SourceFileMissing,
} || std.mem.Allocator.Error;

pub const ParseError = error{ MissingValue, UnknownOption, UnknownOperator, InvalidReportFormat, InvalidJobs, InvalidMode, BackendNotInRun, ConflictingOptions };

/// Pure parser for Phase 1 `run` options (the argv following the `run` command).
/// Only documented options are accepted; anything else is a usage error so the
/// adapter can reject it instead of silently ignoring it.
pub fn parseArgs(args: []const []const u8) ParseError!Options {
    var opts: Options = .{};
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
            i += 1;
            if (i >= args.len) return error.MissingValue;
            // Reject an unknown operator up front; otherwise the filter matches no
            // candidate and the run reports 0 mutants with a clean exit 0, masking a
            // mistyped name in CI (L31).
            if (!config.isKnownOperator(args[i])) return error.UnknownOperator;
            opts.operator_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--mutant")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.mutant_filter = args[i];
        } else if (std.mem.eql(u8, arg, "--report")) {
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
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.output = args[i];
        } else if (std.mem.eql(u8, arg, "--jobs")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            const n = std.fmt.parseInt(usize, args[i], 10) catch return error.InvalidJobs;
            if (n < 1) return error.InvalidJobs; // worker count must be a positive integer
            opts.jobs = n;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            i += 1;
            if (i >= args.len) return error.MissingValue;
            opts.mode_override = safety_modes.parse(args[i]) orelse return error.InvalidMode;
        } else if (std.mem.eql(u8, arg, "--backend")) {
            // The experimental ZIR/AIR backends re-tag the AST candidate set and
            // are reachable only from `list-mutants`; `run` always uses the stable
            // AST backend, so `run --backend` is an explicit usage error rather
            // than a silently ignored no-op (task 114).
            return error.BackendNotInRun;
        } else {
            return error.UnknownOption;
        }
    }
    // --verbose and --quiet select opposite verbosities; accepting both would let
    // quiet silently win and discard the requested verbose output (L44).
    if (opts.verbose and opts.quiet) return error.ConflictingOptions;
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
    // so the config field is honored rather than parsed-and-ignored (M5).
    const no_cache = options.no_cache or !cfg.cache_enabled;

    // Safety/optimization mode matrix (task 058). `mode` is the primary mode
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
        return .{
            .exit_code = 3,
            .report = .{
                .run = baseRun(obs, .baseline_failed),
                .baseline = .{ .status = .failed, .commands = baseline.commands },
                .summary = .{},
                .mutants = &.{},
            },
            .cache = buildCacheMetadata(&.{}, no_cache, obs.zig_cache_namespace),
        };
    }

    // Generate candidates over the discovered files, then filter. The single parse
    // per file also yields each file's same-file tests, reused by selection (L30).
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
    // every mutant from the same source (L5).
    var spec_cache: std.ArrayList(FileSpec) = .empty;
    var job_list: std.ArrayList(Job) = .empty;
    // Index sources by path ONCE so the per-mutant lookup below is O(1), not a
    // linear scan of `files` per candidate (O(M*F)) (L18).
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

    // Phase B (parallel): run each mutant through the injected runner across at
    // most `--jobs` (overriding `run.jobs`) workers. Results are collected by
    // index, so the worker count changes only concurrency -- never which result
    // belongs to which mutant. jobs == 1 runs inline (conservative default). No
    // `arena` allocation happens here; the injected runner uses its own
    // (threadsafe) allocator, and each worker writes a disjoint results slot.
    const results = try arena.alloc(mutant_runner.MutationResult, jobs.len);
    const requested_jobs: usize = if (options.jobs) |j| j else jobsFromConfig(cfg.run_jobs);
    var pctx = ParallelCtx{ .jobs = jobs, .results = results, .mutant_executor = mutant_executor, .mode = mode };
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
    // re-parsing per survivor (L4).
    const reverify_specs = try commandSpecsForConfigured(arena, cfg.test_commands);
    for (jobs, 0..) |job, ji| {
        if (results[ji].status != .survived) continue;
        if (!test_selection.needsConfiguredReverification(job.commands, cfg.test_commands)) continue;
        const reverify = mutant_executor.runSpecs(job.candidate, job.source, reverify_specs, cfg.test_commands, mode);
        results[ji] = try mergeReverification(arena, results[ji], reverify);
    }

    // Mode matrix: when more than one mode is run, record each mode's per-mutant
    // status. The primary mode reuses the parallel results above; additional
    // modes run serially and deterministically (matrix output, not the report's
    // primary status). `mode_grid[mode_index][job_index]` holds the status.
    var mode_grid: [][]report.ResultStatus = &.{};
    if (multi_mode) {
        const grid = try arena.alloc([]report.ResultStatus, matrix_modes.len);
        for (matrix_modes, 0..) |m, mi| {
            const col = try arena.alloc(report.ResultStatus, jobs.len);
            if (m == mode) {
                for (results, 0..) |r, ji| col[ji] = r.status;
            } else {
                for (jobs, 0..) |job, ji| {
                    const narrowed = mutant_executor.runSpecs(job.candidate, job.source, job.command_specs, job.commands, m);
                    // Re-verify a narrowed `survived` against the configured suite
                    // for THIS mode, mirroring Phase B.5. Without it a non-primary
                    // column can record `survived` for a mutant the configured suite
                    // kills in that mode -- understating kills and manufacturing a
                    // spurious mode-dependent signal vs the reverified primary (L27).
                    col[ji] = if (narrowed.status == .survived and test_selection.needsConfiguredReverification(job.commands, cfg.test_commands))
                        mutant_executor.runSpecs(job.candidate, job.source, reverify_specs, cfg.test_commands, m).status
                    else
                        narrowed.status;
                }
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
    const project_hash = try projectHash(arena, files);
    // Hash each unique file's source ONCE; the result-cache key below reuses it per
    // mutant instead of re-hashing the same bytes O(M) times (S3).
    const source_hashes = try buildSourceHashIndex(arena, files);
    for (jobs, results, 0..) |job, result, ji| {
        const mode_matrix: ?[]const report.ModeResult = if (multi_mode) blk: {
            const rows = try arena.alloc(report.ModeResult, matrix_modes.len);
            for (matrix_modes, 0..) |m, mi| rows[mi] = .{ .mode = m, .status = mode_grid[mi][ji] };
            safety_modes.sortModeResults(rows);
            break :blk rows;
        } else null;
        try entries.append(arena, try buildEntry(arena, job.candidate, job.source, result, mode, mode_matrix, job.selection));

        // Compute the deterministic result-cache key (metadata only; reuse stays
        // disabled in Phase 1). A disabled cache skips result keys entirely.
        if (!no_cache) {
            const key = try cache.computeKey(arena, .{
                .mutant_id = job.candidate.id,
                .zentinel_version = obs.zentinel_version,
                .zig_version = obs.zig_version,
                .zig_cache_namespace = obs.zig_cache_namespace,
                .backend = @tagName(job.candidate.backend),
                .backend_version = job.candidate.backend_version,
                .operator = job.candidate.operator,
                .source_hash = source_hashes.get(job.candidate.file) orelse return error.SourceFileMissing,
                .project_hash = project_hash,
                .config_hash = obs.config_hash,
                .test_command = try joinCommands(arena, job.commands),
                .mode = @tagName(mode),
                .environment = "minimal",
                .environment_hash = obs.environment_hash,
            });
            try result_keys.append(arena, .{ .mutant_id = job.candidate.id, .key = key });
        }
    }
    const mutants = try entries.toOwnedSlice(arena);
    report.sortAndAssignDisplayIds(mutants);
    const summary = report.summarize(mutants);

    var exit_code: u8 = 0;
    if (options.fail_on_survivors and summary.survived > 0) exit_code = 1;

    return .{
        .exit_code = exit_code,
        .report = .{
            .run = baseRun(obs, .completed),
            .baseline = .{ .status = .passed, .commands = baseline.commands },
            .summary = summary,
            .mutants = mutants,
        },
        .cache = buildCacheMetadata(try result_keys.toOwnedSlice(arena), no_cache, obs.zig_cache_namespace),
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
/// regression that rebuilt or scanned per mutant would push this above 1 (L18).
pub var source_index_builds: usize = 0;

/// Index source bytes by project-relative path. First occurrence wins, matching
/// the prior `sourceFor` linear scan's first-match semantics (`files` is already
/// de-duplicated by `discover`, so this only matters defensively).
fn buildSourceIndex(arena: std.mem.Allocator, files: []const FileSource) std.mem.Allocator.Error!std.StringHashMap([]const u8) {
    source_index_builds += 1;
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
/// Phase C per-mutant loop; recomputing per mutant would push this to O(M) (S3).
pub var source_hash_count: usize = 0;

/// Index each unique file's source-cache hash (path -> hex SHA-256) ONCE, so the
/// Phase C result-cache key lookup is O(1) per mutant instead of an O(M) re-hash of
/// the same bytes (S3). First occurrence wins, mirroring buildSourceIndex.
fn buildSourceHashIndex(arena: std.mem.Allocator, files: []const FileSource) std.mem.Allocator.Error!std.StringHashMap([]const u8) {
    var index = std.StringHashMap([]const u8).init(arena);
    for (files) |f| {
        const gop = try index.getOrPut(f.path);
        if (!gop.found_existing) {
            source_hash_count += 1;
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

/// Assemble run cache metadata. `--no-cache` disables the result cache (no
/// result keys, mode disabled) but leaves the Zig build-cache isolation metadata
/// intact (docs/PERFORMANCE_STRATEGY.md). Result reuse is never enabled here.
fn buildCacheMetadata(result_keys: []const cache.ResultKey, no_cache: bool, namespace: []const u8) cache.Metadata {
    return .{
        .enabled = !no_cache,
        .mode = if (no_cache) .disabled else .metadata_only,
        .result_keys = if (no_cache) &.{} else result_keys,
        .build_cache = .{ .namespace = namespace, .isolated = true },
    };
}

/// Join selected commands into one deterministic cache-key field.
fn joinCommands(arena: std.mem.Allocator, commands: []const []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (commands, 0..) |c, i| {
        if (i > 0) try out.appendSlice(arena, " && ");
        try out.appendSlice(arena, c);
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
/// by every mutant from that file (L5). All fields are arena-owned, read-only.
const FileSpec = struct {
    file: []const u8,
    resolution: test_selection.Resolution,
    specs: []const command.Spec,
};

/// Test-only counter: how many times the configured commands were parsed into
/// specs. They are constant across the Phase B.5 survivor reverification loop, so
/// this must be 1 per run, not 1 per surviving mutant (L4).
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
/// file, so this must be 1 per unique file, not 1 per mutant (L5).
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
/// this must be 1 per unique file, not 2 (L30).
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
        // computed there and memoized, so selection never re-parses the file (L30).
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

fn enabled(cfg: config.Config, operator: []const u8) bool {
    for (cfg.mutators_enabled) |op| {
        if (std.mem.eql(u8, op, operator)) return true;
    }
    return false;
}

/// The mutant candidates plus the same-file tests discovered during the single
/// per-file parse, so the same-file selection never re-parses a file (L30).
const GeneratedCandidates = struct {
    mutants: []mutant.Mutant,
    same_file_tests: std.StringHashMap([]const report.SelectedTest),
};

/// Recognize Phase 1+2 AST candidates over every file (keeping only those whose
/// operator is enabled in config and that match the optional CLI filters) and, from
/// the same parse, record each file's same-file tests so selection need not
/// re-parse the file (L30).
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
        // instead of parsing the file a second time (L30).
        try same_file_tests.put(f.path, try test_selection.sameFileTests(arena, parsed, f.path));
        try arithmetic.collect(&collector, parsed, f.path, test_ranges);
        try comparison.collect(&collector, parsed, f.path, test_ranges);
        try logical.collect(&collector, parsed, f.path, test_ranges);
        try boolean.collect(&collector, parsed, f.path, test_ranges);
        // Phase-2 stable collectors (task 109): without these the optional,
        // error-path, integer-boundary, and loop-boundary operators load in config
        // but never emit a mutant, silently under-reporting coverage.
        try optional.collect(&collector, parsed, f.path, test_ranges);
        try error_path.collect(&collector, parsed, f.path, test_ranges);
        try integer_boundary.collect(&collector, parsed, f.path, test_ranges);
        try loop_boundary.collect(&collector, parsed, f.path, test_ranges);
    }
    if (collector.invalidCount() > 0) return error.InvalidCandidate;
    const all = try collector.finishRaw();

    var kept: std.ArrayList(mutant.Mutant) = .empty;
    for (all) |c| {
        if (!enabled(cfg, c.operator)) continue;
        if (options.operator_filter) |op| {
            if (!std.mem.eql(u8, c.operator, op)) continue;
        }
        if (options.mutant_filter) |id| {
            if (!std.mem.eql(u8, c.id, id)) continue;
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
        .expected_compile = candidate.expected_compile,
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
