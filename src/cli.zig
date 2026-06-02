// Layer: presentation_adapter
const std = @import("std");
const zentinel = @import("zentinel");

const config_path = "zentinel.toml";
const read_limit = std.Io.Limit.limited(1 << 20);

/// Thin presentation adapter. Pure decision logic lives in the zentinel core:
/// `zentinel.route` decides how to handle argv, `zentinel.dispatch` owns the
/// frozen Phase 0 commands, and `zentinel.check_command`/`zentinel.zig_version`
/// own check and version-policy logic. The adapter performs the I/O the core
/// cannot: resolving config existence, reading config bytes, running
/// `zig version`, and writing output.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    args: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    parent_env: *const std.process.Environ.Map,
) !u8 {
    switch (zentinel.route(args)) {
        .passthrough => return runPassthrough(gpa, io, dir, args, stdout, stderr),
        .version => {
            // stdout stays the policy-only version text; discovered Zig status
            // is environment information on stderr and never makes `version` fatal.
            try stdout.writeAll(zentinel.version_text);
            if (try zentinel.zig_version.statusLine(gpa, discoverZig(gpa, io))) |line| {
                try stderr.print("{s}\n", .{line});
            }
            return 0;
        },
        .check => |globals| {
            const resolved = (try configPathOrReject(gpa, io, dir, globals, stderr)) orelse return 2;
            const result = try zentinel.check_command.run(gpa, .{
                .config_source = readResolvedConfig(gpa, io, dir, resolved),
                .config_path = resolved,
                .zig = discoverZig(gpa, io),
            });
            if (result.stdout.len > 0) try stdout.writeAll(result.stdout);
            if (result.code.len > 0) {
                try stderr.print("error[{s}]: {s}\n", .{ result.code, result.message });
            } else if (result.message.len > 0) {
                try stderr.print("{s}\n", .{result.message});
            }
            return result.exit_code;
        },
        .run => |inv| return runRun(gpa, io, dir, inv, stdout, stderr, parent_env),
        .list_mutants => |inv| return runListMutants(gpa, io, dir, inv, stdout, stderr),
        .doctest => |inv| return runDoctest(gpa, io, dir, inv, stdout, stderr, parent_env),
        .explain => |inv| return runAiCommand(gpa, io, dir, inv, .explain, stdout, stderr),
        .suggest => |inv| return runAiCommand(gpa, io, dir, inv, .suggest, stdout, stderr),
        .review_tests => |inv| return runAiCommand(gpa, io, dir, inv, .review_tests, stdout, stderr),
    }
}

/// Phase 0 commands (help/version-policy/init/unknown/not-implemented) plus the
/// invalid-option diagnostics owned by the frozen `dispatch`.
fn runPassthrough(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    args: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    const config_exists = blk: {
        dir.access(io, config_path, .{}) catch break :blk false;
        break :blk true;
    };

    const outcome = zentinel.dispatch(args, config_exists);

    if (outcome.stdout.len > 0) try stdout.writeAll(outcome.stdout);

    if (outcome.error_code != .none) {
        try stderr.print("error[{s}]: {s}\n", .{ outcome.error_code.token(), outcome.detail });
    } else if (outcome.stderr.len > 0) {
        try stderr.writeAll(outcome.stderr);
    }

    if (outcome.write_config) {
        if (zentinel.config.pathEscapesRoot(io, dir, config_path)) {
            try stderr.writeAll("error: zentinel.toml must stay within the project root\n");
            return 2;
        }
        const text = try zentinel.initConfigText(gpa, outcome.init_test_command);
        try dir.writeFile(io, .{ .sub_path = config_path, .data = text });
    }

    return outcome.exit_code;
}

/// Resolve the config path, writing a clear error and returning null when an
/// explicit `--config` escapes the project root (F-5). The caller exits 2 on null.
fn configPathOrReject(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, globals: zentinel.Globals, stderr: *std.Io.Writer) !?[]const u8 {
    const resolved = zentinel.resolveConfigPathForRoot(gpa, globals) catch |e| switch (e) {
        error.ConfigOutsideRoot => {
            try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --config must stay within the project root\n");
            return null;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (std.fs.path.isAbsolute(globals.root)) {
        var root_dir = dir.openDir(io, globals.root, .{ .iterate = true }) catch return resolved;
        defer root_dir.close(io);
        if (zentinel.config.pathEscapesRoot(io, root_dir, globals.config_path)) {
            try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --config must stay within the project root\n");
            return null;
        }
    } else {
        if (zentinel.config.pathEscapesRoot(io, dir, resolved)) {
            try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --config must stay within the project root\n");
            return null;
        }
    }
    return resolved;
}

fn readResolvedConfig(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) ?[]const u8 {
    if (std.fs.path.isAbsolute(path)) return dir.readFileAlloc(io, path, gpa, read_limit) catch null;
    if (zentinel.config.pathEscapesRoot(io, dir, path)) return null;
    return dir.readFileAlloc(io, path, gpa, read_limit) catch null;
}

/// Run `zig version` and classify the result. Any failure to obtain a version
/// (executable missing, non-zero exit, empty output) is reported as not found.
fn discoverZig(gpa: std.mem.Allocator, io: std.Io) zentinel.zig_version.Discovery {
    const result = std.process.run(gpa, io, .{
        .argv = &.{ "zig", "version" },
        .timeout = .{ .duration = .{ .raw = std.Io.Duration.fromMilliseconds(5000), .clock = .awake } },
    }) catch return .not_found;
    switch (result.term) {
        .exited => |code| if (code != 0) return .not_found,
        else => return .not_found,
    }
    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) return .not_found;
    return .{ .version = trimmed };
}

// --- `zentinel run` (Phase 1) ----------------------------------------------

const run_output_limit = std.Io.Limit.limited(1 << 20);

/// Side-effect context shared by the real baseline and mutant executors. The
/// deterministic orchestration (zentinel.run_command) stays pure; this adapter
/// provides the process execution and per-mutant filesystem workspaces that
/// docs/SANDBOX_SECURITY.md mandates.
const RunCtx = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    root_dir: std.Io.Dir,
    /// Stable cwd label recorded in the report (never a raw workspace path).
    root_label: []const u8,
    run_id: []const u8,
    timeout: std.Io.Timeout,
    /// The minimal command environment actually passed to every spawned test
    /// command (docs/SANDBOX_SECURITY.md). This is what makes the report's
    /// `environment_policy = minimal` label truthful (task 112).
    env: *const std.process.Environ.Map,
    cleanup_failures: std.atomic.Value(u32),
};

/// Run one configured command via direct argv (no shell), honoring the
/// configured timeout. Spawn/exec failures and timeouts are mapped onto the
/// runner's raw-outcome contract so the deterministic classifier owns the verdict.
fn execProcess(rt: *RunCtx, argv: []const []const u8, cwd: std.process.Child.Cwd) zentinel.runner.RawOutcome {
    const result = std.process.run(rt.gpa, rt.io, .{
        .argv = argv,
        .cwd = cwd,
        .stdout_limit = run_output_limit,
        .stderr_limit = run_output_limit,
        .timeout = rt.timeout,
        // Restrict each test command to the documented minimal allowlist
        // (PATH/HOME/TMPDIR/ZIG caches + LC_ALL=C/LANG=C), so the report's
        // `environment_policy = minimal` label is truthful (task 112,
        // docs/SANDBOX_SECURITY.md). Phase 1 still cannot fully OS-sandbox.
        .environ_map = rt.env,
    }) catch |err| {
        if (err == error.Timeout) {
            return .{ .exit_code = null, .timed_out = true, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
        }
        return .{ .exit_code = null, .timed_out = false, .crashed = true, .duration_ms = 0, .stdout = "", .stderr = "" };
    };
    return switch (result.term) {
        .exited => |code| .{
            .exit_code = @as(i64, code),
            .timed_out = false,
            .crashed = false,
            .duration_ms = 0,
            .stdout = result.stdout,
            .stderr = result.stderr,
        },
        // A signal/stop/unknown termination is a crash, not a test failure.
        else => .{
            .exit_code = null,
            .timed_out = false,
            .crashed = true,
            .duration_ms = 0,
            .stdout = result.stdout,
            .stderr = result.stderr,
        },
    };
}

fn baselineRunFn(ctx: *anyopaque, argv: []const []const u8) zentinel.runner.RawOutcome {
    const rt: *RunCtx = @ptrCast(@alignCast(ctx));
    return execProcess(rt, argv, .{ .dir = rt.root_dir });
}

/// A placeholder executor for paths where the deterministic runner returns
/// before executing any command (invalid patch / workspace-creation failure).
fn unusedRunFn(ctx: *anyopaque, argv: []const []const u8) zentinel.runner.RawOutcome {
    _ = ctx;
    _ = argv;
    return .{ .exit_code = null, .timed_out = false, .crashed = true, .duration_ms = 0, .stdout = "", .stderr = "" };
}

const WorkspaceCtx = struct { rt: *RunCtx, dir: std.Io.Dir };

fn workspaceRunFn(ctx: *anyopaque, argv: []const []const u8) zentinel.runner.RawOutcome {
    const w: *WorkspaceCtx = @ptrCast(@alignCast(ctx));
    return execProcess(w.rt, argv, .{ .dir = w.dir });
}

const Workspace = zentinel.worker_pool.Workspace;

/// Build an isolated per-mutant workspace under the zentinel-controlled cache
/// location: copy the project tree (minus caches/VCS), then overwrite the
/// mutated file with the patched bytes. Isolated by run + content-addressed
/// mutant id, so the developer working tree is never modified. The workspace
/// lifecycle (creation + failure-path unwind, L9) lives in worker_pool beside
/// the workspace path helpers; on success the caller owns `ws.dir`/`ws.rel`.
fn setupWorkspace(rt: *RunCtx, m: zentinel.mutant.Mutant, patched: []const u8) !Workspace {
    return zentinel.worker_pool.createMutantWorkspace(rt.io, rt.gpa, rt.root_dir, rt.run_id, m.id, m.file, patched, &rt.cleanup_failures);
}

fn mutantRunFn(
    ctx: *anyopaque,
    m: zentinel.mutant.Mutant,
    source: []const u8,
    commands: []const []const u8,
    mode: zentinel.report.Mode,
) zentinel.mutant_runner.MutationResult {
    const rt: *RunCtx = @ptrCast(@alignCast(ctx));
    var specs: std.ArrayList(zentinel.command.Spec) = .empty;
    for (commands) |original| {
        const argv = switch (zentinel.command.parse(rt.gpa, original) catch @panic("out of memory")) {
            .ok => |a| a,
            .invalid => return zentinel.mutant_runner.run(rt.gpa, m, source, .created, commands, rt.root_label, zentinel.runner.Executor{ .ctx = rt, .runFn = unusedRunFn }, mode) catch @panic("out of memory"),
        };
        specs.append(rt.gpa, .{ .original = original, .argv = argv }) catch @panic("out of memory");
    }
    return mutantRunSpecsFn(ctx, m, source, specs.items, mode);
}

fn mutantRunSpecsFn(
    ctx: *anyopaque,
    m: zentinel.mutant.Mutant,
    source: []const u8,
    commands: []const zentinel.command.Spec,
    mode: zentinel.report.Mode,
) zentinel.mutant_runner.MutationResult {
    const rt: *RunCtx = @ptrCast(@alignCast(ctx));
    const disabled = zentinel.runner.Executor{ .ctx = rt, .runFn = unusedRunFn };

    // Compute patched bytes up front; an invalid patch is classified by the
    // deterministic runner (which re-validates and returns without executing).
    const patched = zentinel.sandbox.apply(rt.gpa, source, m) catch {
        return zentinel.mutant_runner.runSpecs(rt.gpa, m, source, .created, commands, rt.root_label, disabled, mode) catch @panic("out of memory");
    };
    const ws = setupWorkspace(rt, m, patched) catch {
        return zentinel.mutant_runner.runSpecs(rt.gpa, m, source, .create_failed, commands, rt.root_label, disabled, mode) catch @panic("out of memory");
    };
    defer {
        ws.dir.close(rt.io);
        rt.root_dir.deleteTree(rt.io, ws.rel) catch {
            _ = rt.cleanup_failures.fetchAdd(1, .monotonic);
        };
    }
    var wctx = WorkspaceCtx{ .rt = rt, .dir = ws.dir };
    const executor = zentinel.runner.Executor{ .ctx = &wctx, .runFn = workspaceRunFn };
    return zentinel.mutant_runner.runSpecs(rt.gpa, m, source, .created, commands, rt.root_label, executor, mode) catch @panic("out of memory");
}

/// Build the run observation metadata (run id, ISO timestamp, config hash).
fn buildObservation(gpa: std.mem.Allocator, io: std.Io, cfg_bytes: []const u8, zig_label: []const u8, root_label: []const u8) !zentinel.run_command.Observation {
    const ts = std.Io.Timestamp.now(io, .real).toMilliseconds();
    const run_id = try std.fmt.allocPrint(gpa, "run_{x}", .{@as(u64, @intCast(@max(0, ts)))});

    const started_at = try zentinel.report.isoTimestamp(gpa, ts);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cfg_bytes, &digest, .{});
    const config_hash = try std.fmt.allocPrint(gpa, "sha256:{s}", .{std.fmt.bytesToHex(digest, .lower)});

    return .{
        .run_id = run_id,
        .started_at = started_at,
        .project_root = root_label,
        .zentinel_version = zentinel.version,
        .zig_version = zig_label,
        .config_hash = config_hash,
        // Normalized Zig cache namespace label: per-mutant workspaces are
        // isolated under this controlled location (docs/SANDBOX_SECURITY.md).
        .zig_cache_namespace = ".zig-cache/zentinel/workspaces",
        .duration_ms = 0,
    };
}

fn timeoutFromMs(ms: i64) std.Io.Timeout {
    if (ms <= 0) return .none;
    // `.awake` is the monotonic clock that excludes suspend time: the right
    // basis for a wall-bounded test timeout.
    return .{ .duration = .{ .raw = std.Io.Duration.fromMilliseconds(ms), .clock = .awake } };
}

const EffectiveProjectRoot = struct {
    selected: std.Io.Dir,
    nested: ?std.Io.Dir = null,

    fn dir(self: EffectiveProjectRoot) std.Io.Dir {
        return self.nested orelse self.selected;
    }

    fn close(self: *EffectiveProjectRoot, io: std.Io) void {
        if (self.nested) |*nested| nested.close(io);
        self.selected.close(io);
    }
};

fn openEffectiveProjectRoot(
    io: std.Io,
    dir: std.Io.Dir,
    selected_root: []const u8,
    project_root: []const u8,
    stderr: *std.Io.Writer,
) !?EffectiveProjectRoot {
    var selected = try dir.openDir(io, selected_root, .{ .iterate = true });
    errdefer selected.close(io);
    if (std.mem.eql(u8, project_root, ".")) return .{ .selected = selected };
    if (zentinel.config.pathEscapesRoot(io, selected, project_root)) {
        try stderr.writeAll("error[ZNTL_CONFIG_INVALID_VALUE]: project.root must stay within the selected root\n");
        return null;
    }
    const nested = selected.openDir(io, project_root, .{ .iterate = true }) catch |err| {
        try stderr.print("error[ZNTL_CONFIG_INVALID_VALUE]: could not open project.root {s}: {s}\n", .{ project_root, @errorName(err) });
        return null;
    };
    return .{ .selected = selected, .nested = nested };
}

fn defaultLoadedConfig(arena: std.mem.Allocator) !zentinel.config.Config {
    var diag: zentinel.config.Diagnostic = .{};
    return zentinel.config.load(arena, "", &diag) catch |err| switch (err) {
        error.Invalid => unreachable,
        error.OutOfMemory => return error.OutOfMemory,
    };
}

fn doctestConfigOrDefault(
    arena: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    globals: zentinel.Globals,
    stderr: *std.Io.Writer,
) !?zentinel.config.Config {
    const resolved = (try configPathOrReject(arena, io, dir, globals, stderr)) orelse return null;
    const bytes = readResolvedConfig(arena, io, dir, resolved) orelse {
        if (globals.config_explicit) {
            try stderr.print("error: config not found at {s}\n", .{resolved});
            return null;
        }
        return try defaultLoadedConfig(arena);
    };
    var diag: zentinel.config.Diagnostic = .{};
    return zentinel.config.load(arena, bytes, &diag) catch |err| switch (err) {
        error.Invalid => {
            if (globals.config_explicit) {
                try stderr.print("error[{s}]: {s}\n", .{ diag.code.token(), diag.message });
                return null;
            }
            return try defaultLoadedConfig(arena);
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
}

/// `zentinel run`: load config, validate Zig, discover eligible source files
/// from config globs, run the deterministic Phase 1 flow over real executors,
/// then write the JSON report and a concise survivor-focused summary.
fn runRun(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    inv: zentinel.RunInvocation,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    parent_env: *const std.process.Environ.Map,
) !u8 {
    const options = zentinel.run_command.parseArgs(inv.args) catch |err| {
        const detail = switch (err) {
            error.MissingValue => "missing option value",
            error.UnknownOption => "unknown run option",
            error.UnknownOperator => "--operator is not a known operator name; see docs/MUTATOR_SPEC.md for the operator list",
            error.InvalidReportFormat => "--report must be text, json, jsonl, or junit",
            error.InvalidJobs => "--jobs must be a positive integer",
            error.InvalidMode => "--mode must be Debug, ReleaseSafe, ReleaseFast, or ReleaseSmall",
            error.BackendNotInRun => "--backend is list-mutants-only; run always uses the stable AST backend (the experimental ZIR/AIR backends re-tag AST candidates and do no IR analysis)",
        };
        try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: {s}\n", .{detail});
        return 2;
    };

    const cfg_path = (try configPathOrReject(gpa, io, dir, inv.globals, stderr)) orelse return 2;
    const cfg_bytes = readResolvedConfig(gpa, io, dir, cfg_path) orelse {
        try stderr.print("error: config not found at {s}\n", .{cfg_path});
        return 2;
    };
    var diag: zentinel.config.Diagnostic = .{};
    const cfg = zentinel.config.load(gpa, cfg_bytes, &diag) catch {
        try stderr.print("error[{s}]: {s}\n", .{ diag.code.token(), diag.message });
        return 2;
    };

    const zig = discoverZig(gpa, io);
    const fatal_zig = try zentinel.zig_version.fatalStatusLine(gpa, zig);
    if (fatal_zig.len > 0) {
        try stderr.print("{s}\n", .{fatal_zig});
        return zentinel.zig_version.failureExit(zig);
    }
    const zig_label = zentinel.zig_version.supportedLabel(zig).?;

    var selected_root_dir = try dir.openDir(io, inv.globals.root, .{ .iterate = true });
    defer selected_root_dir.close(io);
    var effective_root_dir: ?std.Io.Dir = null;
    defer if (effective_root_dir) |*d| d.close(io);
    if (!std.mem.eql(u8, cfg.project_root, ".")) {
        if (zentinel.config.pathEscapesRoot(io, selected_root_dir, cfg.project_root)) {
            try stderr.writeAll("error[ZNTL_CONFIG_INVALID_VALUE]: project.root must stay within the selected root\n");
            return 2;
        }
        effective_root_dir = selected_root_dir.openDir(io, cfg.project_root, .{ .iterate = true }) catch |err| {
            try stderr.print("error[ZNTL_CONFIG_INVALID_VALUE]: could not open project.root {s}: {s}\n", .{ cfg.project_root, @errorName(err) });
            return 2;
        };
    }
    const root_dir = effective_root_dir orelse selected_root_dir;

    const discovered = try zentinel.project_model.discover(gpa, io, root_dir, cfg.include, cfg.exclude);
    var files: std.ArrayList(zentinel.run_command.FileSource) = .empty;
    for (discovered) |rel| {
        if (zentinel.config.pathEscapesRoot(io, root_dir, rel)) {
            try stderr.print("error[ZNTL_SOURCE_READ_FAILED]: source path must stay within the project root: {s}\n", .{rel});
            return 2;
        }
        const bytes = root_dir.readFileAlloc(io, rel, gpa, read_limit) catch |err| {
            try stderr.print("error[ZNTL_SOURCE_READ_FAILED]: could not read {s}: {s}\n", .{ rel, @errorName(err) });
            return 2;
        };
        try files.append(gpa, .{ .path = rel, .source = bytes });
    }

    // Build the minimal command environment once; every test command this run
    // spawns is restricted to it (docs/SANDBOX_SECURITY.md, task 112).
    var minimal_env = try zentinel.runner.minimalEnviron(gpa, parent_env);
    defer minimal_env.deinit();
    var obs = try buildObservation(gpa, io, cfg_bytes, zig_label, "<project>");
    obs.environment_hash = try zentinel.cache.environmentHash(gpa, &minimal_env);

    var rt = RunCtx{
        .gpa = gpa,
        .io = io,
        .root_dir = root_dir,
        .root_label = "<project>",
        .run_id = obs.run_id,
        .timeout = timeoutFromMs(cfg.test_timeout_ms),
        .env = &minimal_env,
        .cleanup_failures = std.atomic.Value(u32).init(0),
    };
    const baseline_executor = zentinel.runner.Executor{ .ctx = &rt, .runFn = baselineRunFn };
    const mutant_executor = zentinel.run_command.MutantRunner{ .ctx = &rt, .runFn = mutantRunFn, .runSpecsFn = mutantRunSpecsFn };

    const outcome = zentinel.run_command.run(gpa, cfg, files.items, options, baseline_executor, mutant_executor, obs) catch |err| switch (err) {
        error.OutputOutsideRoot => {
            try stderr.writeAll("error: --output must stay within the project root\n");
            return 2;
        },
        error.BackendParseError => {
            if (try zentinel.run_command.firstBackendParseError(gpa, files.items)) |path| {
                try stderr.print("error[ZNTL_BACKEND_PARSE_ERROR]: could not parse source file {s}\n", .{path});
            } else {
                try stderr.writeAll("error[ZNTL_BACKEND_PARSE_ERROR]: could not parse one or more source files\n");
            }
            return 2;
        },
        error.InvalidCandidate => {
            try stderr.writeAll("error[ZNTL_INTERNAL_INVARIANT]: AST backend emitted an invalid mutation candidate\n");
            return 4;
        },
        error.InvalidCommand => {
            try stderr.writeAll("error[ZNTL_CONFIG_INVALID_COMMAND]: configured test command cannot be parsed\n");
            return 2;
        },
        error.SourceFileMissing => {
            try stderr.writeAll("error[ZNTL_INTERNAL_INVARIANT]: generated mutant references a missing source file\n");
            return 4;
        },
        error.OutOfMemory => return err,
    };

    // Remove the per-run workspace container that setupWorkspace materialized via
    // createDirPath (.zig-cache/zentinel/workspaces/{run_id}). mutantRunSpecsFn
    // deletes each content-addressed per-mutant leaf, but nothing removed the
    // {run_id} parent, so every invocation leaked one stale `run_<x>` dir under
    // the controlled cache namespace. Best-effort and counted like the per-mutant
    // cleanup so a failure surfaces in the warning below (L8).
    {
        const run_base = try zentinel.worker_pool.workspaceRunBase(gpa, rt.run_id);
        rt.root_dir.deleteTree(rt.io, run_base) catch {
            _ = rt.cleanup_failures.fetchAdd(1, .monotonic);
        };
    }

    try zentinel.emitCleanupWarningIfNeeded(rt.cleanup_failures.load(.monotonic), stderr);

    // Write the JSON report to the resolved output path (under the project root).
    const json = try zentinel.report.toJson(gpa, outcome.report);
    const out_path = options.output orelse try std.fmt.allocPrint(gpa, "{s}/report.json", .{cfg.report_output_dir});
    // Symlink-safe containment (F-3): the string-level --output check
    // (run_command.run -> OutputOutsideRoot) already rejected absolute and `..`
    // paths, but `writeFile` follows symlinks in the sub-path, so an in-tree
    // symlink that leaves the project tree could redirect the report outside the
    // root. Refuse a symlinked output component before creating any directory or
    // writing, so an untrusted checkout cannot escape the analyzed project.
    if (zentinel.config.pathEscapesRoot(io, root_dir, out_path)) {
        try stderr.writeAll("error: --output must stay within the project root\n");
        return 2;
    }
    if (std.fs.path.dirname(out_path)) |parent| {
        root_dir.createDirPath(io, parent) catch {};
    }
    root_dir.writeFile(io, .{ .sub_path = out_path, .data = json }) catch |err| {
        try stderr.print("error: could not write report to {s}: {s}\n", .{ out_path, @errorName(err) });
        return 2;
    };

    // Emit deterministic cache metadata alongside the report (best-effort). The
    // cache write shares the symlink containment guard; an escape is skipped
    // rather than fatal because the cache is best-effort.
    const cache_json = try zentinel.cache.toJson(gpa, outcome.cache);
    // The cache artifact goes under the configured cache.directory (M5), not the
    // report output dir; the symlink-containment guard and parent-dir creation
    // below keep the write safe and best-effort.
    const cache_path = try std.fmt.allocPrint(gpa, "{s}/cache.json", .{cfg.cache_directory});
    if (!zentinel.config.pathEscapesRoot(io, root_dir, cache_path)) {
        if (std.fs.path.dirname(cache_path)) |parent| root_dir.createDirPath(io, parent) catch {};
        root_dir.writeFile(io, .{ .sub_path = cache_path, .data = cache_json }) catch {};
    }

    // The canonical JSON report is always written to the output path; --report
    // selects only the stdout rendering, so the canonical report data is the same
    // regardless of format. --verbose/--quiet affect only the text rendering.
    const verbosity: zentinel.report_text.Verbosity =
        if (options.quiet) .quiet else if (options.verbose) .verbose else .normal;
    const rendered = switch (options.report_format) {
        .text => try zentinel.report_text.render(gpa, outcome.report, verbosity),
        .json => json,
        .jsonl => try zentinel.report_jsonl.render(gpa, outcome.report),
        .junit => try zentinel.report_junit.render(gpa, outcome.report, options.fail_on_survivors),
    };
    try stdout.writeAll(rendered);
    // Canonical JSON has no trailing newline; the other renderers already end in one.
    if (options.report_format == .json) try stdout.writeAll("\n");
    return outcome.exit_code;
}

// --- `zentinel list-mutants` (Phase 1) -------------------------------------

/// `zentinel list-mutants`: load config, discover eligible files from config
/// globs, generate the stable AST candidate set, and render a deterministic
/// text or JSON listing. No baseline, no executor, no workspace: listing never
/// patches a file or runs a test command.
fn runListMutants(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    inv: zentinel.RunInvocation,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    // Extract the experimental `--backend <ast|zir|air>` opt-in here in the
    // adapter (task 056): the frozen list-mutants parser owns only
    // `--operator`/`--format` and stays unchanged. Default is the stable AST.
    var backend: []const u8 = "ast";
    var filtered: std.ArrayList([]const u8) = .empty;
    {
        var i: usize = 0;
        while (i < inv.args.len) : (i += 1) {
            const a = inv.args[i];
            if (std.mem.eql(u8, a, "--backend")) {
                i += 1;
                if (i >= inv.args.len) {
                    try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --backend requires a value\n");
                    return 2;
                }
                backend = inv.args[i];
                if (!std.mem.eql(u8, backend, "ast") and !std.mem.eql(u8, backend, "zir") and !std.mem.eql(u8, backend, "air")) {
                    try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --backend must be 'ast', 'zir', or 'air'\n");
                    return 2;
                }
            } else {
                try filtered.append(gpa, a);
            }
        }
    }

    const options = zentinel.list_mutants_command.parseArgs(filtered.items) catch |err| {
        const detail = switch (err) {
            error.MissingValue => "missing option value",
            error.UnknownOption => "unknown list-mutants option",
            error.UnknownOperator => "--operator is not a known operator name; see docs/MUTATOR_SPEC.md for the operator list",
            error.InvalidFormat => "--format must be 'text' or 'json'",
        };
        try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: {s}\n", .{detail});
        return 2;
    };

    const cfg_path = (try configPathOrReject(gpa, io, dir, inv.globals, stderr)) orelse return 2;
    const cfg_bytes = readResolvedConfig(gpa, io, dir, cfg_path) orelse {
        try stderr.print("error: config not found at {s}\n", .{cfg_path});
        return 2;
    };
    var diag: zentinel.config.Diagnostic = .{};
    const cfg = zentinel.config.load(gpa, cfg_bytes, &diag) catch {
        try stderr.print("error[{s}]: {s}\n", .{ diag.code.token(), diag.message });
        return 2;
    };

    var roots = (try openEffectiveProjectRoot(io, dir, inv.globals.root, cfg.project_root, stderr)) orelse return 2;
    defer roots.close(io);
    const root_dir = roots.dir();

    const discovered = try zentinel.project_model.discover(gpa, io, root_dir, cfg.include, cfg.exclude);
    var files: std.ArrayList(zentinel.list_mutants_command.FileSource) = .empty;
    for (discovered) |rel| {
        if (zentinel.config.pathEscapesRoot(io, root_dir, rel)) {
            try stderr.print("error[ZNTL_SOURCE_READ_FAILED]: source path must stay within the project root: {s}\n", .{rel});
            return 2;
        }
        const bytes = root_dir.readFileAlloc(io, rel, gpa, read_limit) catch |err| {
            try stderr.print("error[ZNTL_SOURCE_READ_FAILED]: could not read {s}: {s}\n", .{ rel, @errorName(err) });
            return 2;
        };
        try files.append(gpa, .{ .path = rel, .source = bytes });
    }

    const candidates = zentinel.list_mutants_command.generate(gpa, cfg, files.items, options.operator_filter) catch |err| switch (err) {
        error.BackendParseError => {
            if (try zentinel.run_command.firstBackendParseError(gpa, files.items)) |path| {
                try stderr.print("error[ZNTL_BACKEND_PARSE_ERROR]: could not parse source file {s}\n", .{path});
            } else {
                try stderr.writeAll("error[ZNTL_BACKEND_PARSE_ERROR]: could not parse one or more source files\n");
            }
            return 2;
        },
        error.InvalidCandidate => {
            try stderr.writeAll("error[ZNTL_INTERNAL_INVARIANT]: AST backend emitted an invalid mutation candidate\n");
            return 4;
        },
        error.OutOfMemory => return err,
    };

    // Experimental backend opt-in (task 056: zir). The stable AST default is
    // unchanged; experimental backends are gated by config and emit out-of-report
    // diagnostics for operators with no exact source mapping.
    if (std.mem.eql(u8, backend, "zir")) {
        const listing = zentinel.zir_backend.experimentalListing(gpa, cfg, candidates, backend) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ExperimentalBackendNotEnabled => {
                try stderr.print("error[ZNTL_CONFIG_EXPERIMENTAL_BACKEND]: backend '{s}' requires explicit opt-in via [backend] experimental\n", .{backend});
                return 2;
            },
            error.BackendNotImplemented => {
                try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: backend '{s}' is not implemented yet\n", .{backend});
                return 2;
            },
        };
        const rendered = switch (options.format) {
            .text => try zentinel.list_mutants_command.renderText(gpa, listing.candidates),
            .json => try zentinel.list_mutants_command.renderJson(gpa, listing.candidates),
        };
        try stdout.writeAll(rendered);
        if (options.format == .json) try stdout.writeAll("\n");
        // Out-of-report backend diagnostics: stderr only, never report fields.
        for (listing.diagnostics) |d| {
            try stderr.writeAll(try zentinel.zir_backend.renderDiagnosticNote(gpa, d));
        }
        return 0;
    } else if (std.mem.eql(u8, backend, "air")) {
        const listing = zentinel.air_backend.experimentalListing(gpa, cfg, candidates, backend) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.ExperimentalBackendNotEnabled => {
                try stderr.print("error[ZNTL_CONFIG_EXPERIMENTAL_BACKEND]: backend '{s}' requires explicit opt-in via [backend] experimental\n", .{backend});
                return 2;
            },
            error.BackendNotImplemented => {
                try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: backend '{s}' is not implemented yet\n", .{backend});
                return 2;
            },
        };
        const rendered = switch (options.format) {
            .text => try zentinel.list_mutants_command.renderText(gpa, listing.candidates),
            .json => try zentinel.list_mutants_command.renderJson(gpa, listing.candidates),
        };
        try stdout.writeAll(rendered);
        if (options.format == .json) try stdout.writeAll("\n");
        // Out-of-report AIR diagnostics (with source_mapping + safety mode):
        // stderr only, never report fields.
        for (listing.diagnostics) |d| {
            try stderr.writeAll(try zentinel.air_backend.renderDiagnosticNote(gpa, d));
        }
        return 0;
    }

    const rendered = switch (options.format) {
        .text => try zentinel.list_mutants_command.renderText(gpa, candidates),
        .json => try zentinel.list_mutants_command.renderJson(gpa, candidates),
    };
    try stdout.writeAll(rendered);
    if (options.format == .json) try stdout.writeAll("\n");
    return 0;
}

// --- `zentinel doctest` (Phase 1, normal doctests) -------------------------

const default_doctest_file = "docs/CLI_SPEC.md";

const DoctestCtx = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    root_dir: std.Io.Dir,
    timeout: std.Io.Timeout,
    env: *const std.process.Environ.Map,
};

/// Execute a doctest CLI command (already validated to begin with `zentinel`)
/// via direct argv, no shell. The deterministic runner owns the verdict.
fn doctestExecFn(ctx: *anyopaque, argv: []const []const u8) zentinel.runner.RawOutcome {
    const rt: *DoctestCtx = @ptrCast(@alignCast(ctx));
    const result = std.process.run(rt.gpa, rt.io, .{
        .argv = argv,
        .cwd = .{ .dir = rt.root_dir },
        .stdout_limit = run_output_limit,
        .stderr_limit = run_output_limit,
        .timeout = rt.timeout,
        .environ_map = rt.env,
    }) catch |err| {
        if (err == error.Timeout) return .{ .exit_code = null, .timed_out = true, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
        return .{ .exit_code = null, .timed_out = false, .crashed = true, .duration_ms = 0, .stdout = "", .stderr = "" };
    };
    return switch (result.term) {
        .exited => |code| .{ .exit_code = @as(i64, code), .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = result.stdout, .stderr = result.stderr },
        else => .{ .exit_code = null, .timed_out = false, .crashed = true, .duration_ms = 0, .stdout = result.stdout, .stderr = result.stderr },
    };
}

const DoctestWsCtx = struct { gpa: std.mem.Allocator, io: std.Io, root_dir: std.Io.Dir };

/// Materialize a doctest workspace under the zentinel-controlled cache location.
/// Every planned path is confined under the workspace dir, so repository sources
/// are never written.
fn doctestWsFn(ctx: *anyopaque, plan: zentinel.doctest.workspace.Plan) zentinel.doctest.workspace.MaterializeError!void {
    const w: *DoctestWsCtx = @ptrCast(@alignCast(ctx));
    if (!zentinel.doctest.workspace.isConfined(plan)) return error.WorkspaceCreateFailed;
    if (zentinel.config.pathEscapesRoot(w.io, w.root_dir, plan.dir)) return error.WorkspaceCreateFailed;
    w.root_dir.createDirPath(w.io, plan.dir) catch return error.WorkspaceCreateFailed;
    for (plan.files) |f| {
        if (zentinel.config.pathEscapesRoot(w.io, w.root_dir, f.rel_path)) return error.WorkspaceCreateFailed;
        if (std.fs.path.dirname(f.rel_path)) |parent| {
            w.root_dir.createDirPath(w.io, parent) catch return error.WorkspaceCreateFailed;
        }
        w.root_dir.writeFile(w.io, .{ .sub_path = f.rel_path, .data = f.contents }) catch return error.WorkspaceCreateFailed;
    }
}

/// `zentinel doctest`: read the target doc, execute its normal doctests through
/// real process/workspace adapters, and emit a deterministic text or JSON
/// zentinel.doctest.report.v1 report.
/// Adapter for the advisory AI commands `explain`, `suggest`, and `review-tests`
/// (task 054). Parses command-local options, reads normalized config and the
/// selected mutation report read-only, then delegates to the deterministic
/// `ai.command` engine. AI-only failures print their documented `ZNTL_AI_*` code
/// and never touch a report.
fn runAiCommand(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    inv: zentinel.RunInvocation,
    flow: zentinel.ai.command.Flow,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var mutant_ref: ?[]const u8 = null;
    var ai_opts = zentinel.ai.command.SharedOptions{};
    var i: usize = 0;
    while (i < inv.args.len) : (i += 1) {
        const a = inv.args[i];
        switch (zentinel.ai.command.parseSharedOption(inv.args, &i, &ai_opts)) {
            .consumed => continue,
            .err => |detail| return aiOptionError(stderr, detail),
            .not_shared => {},
        }
        if (std.mem.startsWith(u8, a, "--")) {
            return aiOptionError(stderr, "unknown AI command option");
        } else if (flow != .review_tests and mutant_ref == null) {
            mutant_ref = a;
        } else {
            return aiOptionError(stderr, "unexpected positional argument");
        }
    }
    const provider_override = ai_opts.provider_override;
    const input_report = ai_opts.input_report;
    const format = ai_opts.format;
    if (flow != .review_tests and mutant_ref == null) {
        return aiOptionError(stderr, "missing <mutant-ref>");
    }
    // Read-side path containment (F-5): an out-of-root --input-report escapes the
    // project root, so reject it like the write-side --output guard.
    if (zentinel.readPathOutsideRootOption(inv.args)) |opt| {
        return aiOptionError(stderr, try std.fmt.allocPrint(arena, "{s} must stay within the project root", .{opt}));
    }

    const ai_cfg = (try aiSettings(arena, gpa, io, dir, inv.globals, stderr)) orelse return 2;

    var roots = (try openEffectiveProjectRoot(io, dir, inv.globals.root, ai_cfg.project_root, stderr)) orelse return 2;
    defer roots.close(io);
    const root_dir = roots.dir();
    const report_path = input_report orelse zentinel.ai.command.default_report_path;
    if (zentinel.config.pathEscapesRoot(io, root_dir, report_path)) {
        return aiOptionError(stderr, "--input-report must stay within the project root");
    }
    const report_json: ?[]const u8 = root_dir.readFileAlloc(io, report_path, arena, read_limit) catch null;

    const input = zentinel.ai.command.Input{
        .flow = flow,
        .mutant_ref = mutant_ref,
        .provider_override = provider_override,
        .report_json = report_json,
        .settings = ai_cfg.settings,
    };

    const out = zentinel.ai.command.run(arena, input, format) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => |f| {
            try stderr.print("error[{s}]: advisory AI command failed\n", .{zentinel.ai.command.failureToken(f)});
            return zentinel.ai.command.failureExit(f);
        },
    };

    try stdout.writeAll(out.body);
    if (out.format == .json) try stdout.writeAll("\n");
    return out.exit_code;
}

fn aiOptionError(stderr: *std.Io.Writer, detail: []const u8) !u8 {
    try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: {s}\n", .{detail});
    return 2;
}

const AiCliSettings = struct {
    settings: zentinel.ai.command.Settings,
    project_root: []const u8,
};

/// Build advisory AI settings from normalized config. An omitted or invalid
/// implicit config keeps AI disabled; an explicit missing/invalid config is a
/// usage error and never falls through to provider execution.
fn aiSettings(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    globals: zentinel.Globals,
    stderr: *std.Io.Writer,
) !?AiCliSettings {
    const zig_label: []const u8 = zentinel.zig_version.supportedLabel(discoverZig(gpa, io)) orelse "unknown";
    var settings = zentinel.ai.command.Settings{
        .ai_enabled = false,
        .config_mode = .disabled,
        .remote_allowed = false,
        .redact_patterns = &zentinel.ai.command.default_redact_patterns,
        .project_name = zentinel.project_name,
        .zig_version = zig_label,
        .zentinel_version = zentinel.version,
    };
    const resolved = (try configPathOrReject(arena, io, dir, globals, stderr)) orelse return null;
    const bytes = readResolvedConfig(arena, io, dir, resolved) orelse {
        if (globals.config_explicit) {
            try stderr.print("error: config not found at {s}\n", .{resolved});
            return null;
        }
        return .{ .settings = settings, .project_root = "." };
    };
    var diag: zentinel.config.Diagnostic = .{};
    const cfg = zentinel.config.load(arena, bytes, &diag) catch |err| switch (err) {
        error.Invalid => {
            if (globals.config_explicit) {
                try stderr.print("error[{s}]: {s}\n", .{ diag.code.token(), diag.message });
                return null;
            }
            return .{ .settings = settings, .project_root = "." };
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
    settings.ai_enabled = cfg.ai_enabled;
    settings.config_mode = zentinel.ai.provider.modeFromName(cfg.ai_provider) orelse .disabled;
    settings.remote_allowed = cfg.ai_remote_allowed;
    settings.redact_patterns = cfg.ai_redact_patterns;
    settings.project_name = cfg.project_name;
    return .{ .settings = settings, .project_root = cfg.project_root };
}

/// Adapter for the advisory doctest-AI subcommands (task 055). Parses
/// command-local options, reads config and the selected doctest report or docs
/// path read-only, then delegates to the deterministic `ai.doctest_command`
/// engine. Doctest AI is advisory only and never edits docs, snapshots, or
/// reports; AI/doctest failures print their documented codes.
fn runDoctestAi(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    inv: zentinel.RunInvocation,
    flow: zentinel.ai.doctest_command.Flow,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var positional: ?[]const u8 = null;
    var file_opt: ?[]const u8 = null;
    var ai_opts = zentinel.ai.command.SharedOptions{};

    var i: usize = 1; // skip the subcommand token at inv.args[0]
    while (i < inv.args.len) : (i += 1) {
        const a = inv.args[i];
        // `--file` is doctest-specific; the rest are the shared AI options (L16).
        if (std.mem.eql(u8, a, "--file")) {
            i += 1;
            if (i >= inv.args.len) return aiOptionError(stderr, "--file requires a value");
            file_opt = inv.args[i];
            continue;
        }
        switch (zentinel.ai.command.parseSharedOption(inv.args, &i, &ai_opts)) {
            .consumed => continue,
            .err => |detail| return aiOptionError(stderr, detail),
            .not_shared => {},
        }
        if (std.mem.startsWith(u8, a, "--")) {
            return aiOptionError(stderr, "unknown doctest AI option");
        } else if (positional == null) {
            positional = a;
        } else {
            return aiOptionError(stderr, "unexpected positional argument");
        }
    }
    const input_report = ai_opts.input_report;
    const provider_override = ai_opts.provider_override;
    const format = ai_opts.format;

    const flow_is_case = (flow == .explain_doctest_failure or flow == .review_snapshot);
    const doc_path: ?[]const u8 = switch (flow) {
        .suggest_doctest => positional,
        .suggest_missing_doctests => file_opt,
        else => null,
    };
    const case_ref: ?[]const u8 = if (flow_is_case) positional else null;

    // Read-side path containment (F-5): reject an out-of-root --input-report,
    // --file, or positional documentation path so reads honor the write-side
    // root-containment contract.
    if (zentinel.readPathOutsideRootOption(inv.args)) |opt| {
        return aiOptionError(stderr, try std.fmt.allocPrint(arena, "{s} must stay within the project root", .{opt}));
    }
    if (doc_path) |d| {
        if (zentinel.config.isOutsideRoot(d)) return aiOptionError(stderr, "documentation path must stay within the project root");
    }

    const ai_cfg = (try aiSettings(arena, gpa, io, dir, inv.globals, stderr)) orelse return 2;

    // A required positional missing (doc-path for suggest, case-ref for explain /
    // review-snapshot) is a CLI usage error, surfaced like the top-level AI commands'
    // `missing <mutant-ref>`/`missing <survivor-ref>` guards instead of being
    // forwarded as a null ref the engine reports as an opaque DOC/CASE_NOT_FOUND
    // (L32). Checked after config/--config validation so a bad --config still wins.
    if (zentinel.ai.doctest_command.missingPositional(flow, positional)) |detail| {
        return aiOptionError(stderr, detail);
    }

    var roots = (try openEffectiveProjectRoot(io, dir, inv.globals.root, ai_cfg.project_root, stderr)) orelse return 2;
    defer roots.close(io);
    const root_dir = roots.dir();

    if (doc_path) |d| {
        if (zentinel.config.pathEscapesRoot(io, root_dir, d)) return aiOptionError(stderr, "documentation path must stay within the project root");
    }

    const doc_exists = blk: {
        const d = doc_path orelse break :blk false;
        root_dir.access(io, d, .{}) catch break :blk false;
        break :blk true;
    };
    const report_json: ?[]const u8 = blk: {
        if (flow_is_case) {
            const rp = input_report orelse zentinel.ai.doctest_command.default_report_path;
            if (zentinel.config.pathEscapesRoot(io, root_dir, rp)) return aiOptionError(stderr, "--input-report must stay within the project root");
            break :blk root_dir.readFileAlloc(io, rp, arena, read_limit) catch null;
        } else if (input_report) |rp| {
            if (zentinel.config.pathEscapesRoot(io, root_dir, rp)) return aiOptionError(stderr, "--input-report must stay within the project root");
            break :blk root_dir.readFileAlloc(io, rp, arena, read_limit) catch null;
        }
        break :blk null;
    };

    const out = zentinel.ai.doctest_command.run(arena, .{
        .flow = flow,
        .case_ref = case_ref,
        .doc_path = doc_path,
        .doc_exists = doc_exists,
        .provider_override = provider_override,
        .report_json = report_json,
        .settings = ai_cfg.settings,
    }, format) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => |f| {
            try stderr.print("error[{s}]: advisory doctest AI command failed\n", .{zentinel.ai.doctest_command.failureToken(f)});
            return zentinel.ai.doctest_command.failureExit(f);
        },
    };

    try stdout.writeAll(out.body);
    if (out.format == .json) try stdout.writeAll("\n");
    return out.exit_code;
}

/// Adapter for `zentinel doctest explain-survivor <survivor-ref>` (task 067).
/// Reads config and the selected mutation-aware doctest report read-only and
/// delegates to the deterministic survivor engine. Advisory only: it never
/// changes a survivor's status, the report, snapshots, or documentation.
fn runDoctestSurvivorAi(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    inv: zentinel.RunInvocation,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var survivor_ref: ?[]const u8 = null;
    var ai_opts = zentinel.ai.command.SharedOptions{};

    var i: usize = 1; // skip the subcommand token at inv.args[0]
    while (i < inv.args.len) : (i += 1) {
        const a = inv.args[i];
        switch (zentinel.ai.command.parseSharedOption(inv.args, &i, &ai_opts)) {
            .consumed => continue,
            .err => |detail| return aiOptionError(stderr, detail),
            .not_shared => {},
        }
        if (std.mem.startsWith(u8, a, "--")) {
            return aiOptionError(stderr, "unknown doctest AI option");
        } else if (survivor_ref == null) {
            survivor_ref = a;
        } else {
            return aiOptionError(stderr, "unexpected positional argument");
        }
    }
    const input_report = ai_opts.input_report;
    const provider_override = ai_opts.provider_override;
    const format = ai_opts.format;
    if (survivor_ref == null) return aiOptionError(stderr, "missing <survivor-ref>");
    // Read-side path containment (F-5): reject an out-of-root --input-report.
    if (zentinel.readPathOutsideRootOption(inv.args)) |opt| {
        return aiOptionError(stderr, try std.fmt.allocPrint(arena, "{s} must stay within the project root", .{opt}));
    }

    const ai_cfg = (try aiSettings(arena, gpa, io, dir, inv.globals, stderr)) orelse return 2;

    var roots = (try openEffectiveProjectRoot(io, dir, inv.globals.root, ai_cfg.project_root, stderr)) orelse return 2;
    defer roots.close(io);
    const root_dir = roots.dir();
    const report_path = input_report orelse zentinel.ai.doctest_command.default_report_path;
    if (zentinel.config.pathEscapesRoot(io, root_dir, report_path)) {
        return aiOptionError(stderr, "--input-report must stay within the project root");
    }
    const report_json: ?[]const u8 = root_dir.readFileAlloc(io, report_path, arena, read_limit) catch null;

    const out = zentinel.ai.doctest_command.runSurvivor(arena, .{
        .survivor_ref = survivor_ref,
        .provider_override = provider_override,
        .report_json = report_json,
        .settings = ai_cfg.settings,
    }, format) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => |f| {
            try stderr.print("error[{s}]: advisory doctest AI command failed\n", .{zentinel.ai.doctest_command.failureToken(f)});
            return zentinel.ai.doctest_command.failureExit(f);
        },
    };

    try stdout.writeAll(out.body);
    if (out.format == .json) try stdout.writeAll("\n");
    return out.exit_code;
}

fn runDoctest(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    inv: zentinel.RunInvocation,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    parent_env: *const std.process.Environ.Map,
) !u8 {
    // A recognized named AI subcommand in the first slot dispatches BEFORE the
    // experimental `--mutate` flag scan, so `doctest suggest --mutate` runs the
    // suggest flow instead of being hijacked by `--mutate` (task 039/055/067, L22).
    switch (zentinel.doctest_command.route(inv.args)) {
        .mutate => return runDoctestMutate(gpa, io, dir, inv, stdout, stderr, parent_env),
        .explain => return runDoctestAi(gpa, io, dir, inv, .explain_doctest_failure, stdout, stderr),
        .suggest => return runDoctestAi(gpa, io, dir, inv, .suggest_doctest, stdout, stderr),
        .review_snapshot => return runDoctestAi(gpa, io, dir, inv, .review_snapshot, stdout, stderr),
        .suggest_missing => return runDoctestAi(gpa, io, dir, inv, .suggest_missing_doctests, stdout, stderr),
        .explain_survivor => return runDoctestSurvivorAi(gpa, io, dir, inv, stdout, stderr),
        .parse => {},
    }

    const options = zentinel.doctest_command.parseArgs(inv.args) catch |err| {
        const detail = switch (err) {
            error.MissingValue => "missing option value",
            error.UnknownOption => "unknown doctest option",
            error.InvalidFormat => "--format must be 'text' or 'json'",
            error.UnsupportedSubcommand => "doctest subcommand not implemented yet",
        };
        try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: {s}\n", .{detail});
        return 2;
    };

    const doc_file = options.file orelse default_doctest_file;
    const cfg = (try doctestConfigOrDefault(gpa, io, dir, inv.globals, stderr)) orelse return 2;

    const zig = discoverZig(gpa, io);
    const fatal_zig = try zentinel.zig_version.fatalStatusLine(gpa, zig);
    if (fatal_zig.len > 0) {
        try stderr.print("{s}\n", .{fatal_zig});
        return zentinel.zig_version.failureExit(zig);
    }
    const zig_label = zentinel.zig_version.supportedLabel(zig).?;

    var roots = (try openEffectiveProjectRoot(io, dir, inv.globals.root, cfg.project_root, stderr)) orelse return 2;
    defer roots.close(io);
    const root_dir = roots.dir();

    if (zentinel.config.pathEscapesRoot(io, root_dir, doc_file)) {
        try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --file must stay within the project root\n");
        return 2;
    }

    const source = root_dir.readFileAlloc(io, doc_file, gpa, read_limit) catch {
        try stderr.print("error: documentation file not found at {s}\n", .{try zentinel.redactCliDiagnosticPath(gpa, doc_file)});
        return 2;
    };

    const ts = std.Io.Timestamp.now(io, .real).toMilliseconds();
    const run_id = try std.fmt.allocPrint(gpa, "doctest_run_{x}", .{@as(u64, @intCast(@max(0, ts)))});
    const started_at = try zentinel.report.isoTimestamp(gpa, ts);
    const fmt_label: []const u8 = switch (options.format) {
        .text => "text",
        .json => "json",
    };
    const command = try std.fmt.allocPrint(gpa, "zentinel doctest --file {s} --format {s}", .{ doc_file, fmt_label });

    var minimal_env = try zentinel.runner.minimalEnviron(gpa, parent_env);
    defer minimal_env.deinit();

    var dctx = DoctestCtx{
        .gpa = gpa,
        .io = io,
        .root_dir = root_dir,
        .timeout = timeoutFromMs(cfg.test_timeout_ms),
        .env = &minimal_env,
    };
    var wctx = DoctestWsCtx{ .gpa = gpa, .io = io, .root_dir = root_dir };
    const deps = zentinel.doctest_command.Deps{
        .executor = .{ .ctx = &dctx, .runFn = doctestExecFn },
        .provider = .{ .ctx = &wctx, .materializeFn = doctestWsFn },
    };
    const obs = zentinel.doctest_command.Observation{
        .run_id = run_id,
        .started_at = started_at,
        .zentinel_version = zentinel.version,
        .zig_version = zig_label,
        .project_root = "<project>",
        .command = command,
    };

    const out = zentinel.doctest_command.run(gpa, options, doc_file, source, obs, deps) catch |err| switch (err) {
        error.CaseNotFound => {
            try stderr.print("error[ZNTL_DOCTEST_CASE_NOT_FOUND]: --case did not resolve to exactly one case\n", .{});
            return 2;
        },
        // A per-case workspace-creation failure no longer reaches here: the runner
        // isolates it as an `.invalid` case so the run still produces a report
        // (L12). Only OOM remains as a run-wide internal error.
        error.OutOfMemory => return err,
    };

    const rendered = switch (options.format) {
        .text => try zentinel.doctest_command.renderText(gpa, out.report),
        .json => try zentinel.doctest.report.toJson(gpa, out.report),
    };
    try stdout.writeAll(rendered);
    if (options.format == .json) try stdout.writeAll("\n");
    return out.exit_code;
}

// --- `zentinel doctest --mutate` (experimental, fixture docs only) ----------

const DoctestMutateCtx = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    root_dir: std.Io.Dir,
    timeout: std.Io.Timeout,
    env: *const std.process.Environ.Map,
};

fn doctestMutateRelPath(gpa: std.mem.Allocator, mutated_source: []const u8) ?[]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(mutated_source, &digest, .{});
    return std.fmt.allocPrint(gpa, ".zig-cache/zentinel/doctest-mutate/{s}.zig", .{std.fmt.bytesToHex(digest[0..8], .lower)}) catch null;
}

fn doctestMutateCommandFn(ctx: *anyopaque, mutated_source: []const u8) zentinel.doctest.mutation_experiment.StableCommand {
    const rt: *DoctestMutateCtx = @ptrCast(@alignCast(ctx));
    const rel = doctestMutateRelPath(rt.gpa, mutated_source) orelse return .{ .original = "zig test src/doctest.zig", .argv = &.{ "zig", "test", "src/doctest.zig" }, .cwd = "." };
    const original = std.fmt.allocPrint(rt.gpa, "zig test {s}", .{rel}) catch return .{ .original = "zig test src/doctest.zig", .argv = &.{ "zig", "test", "src/doctest.zig" }, .cwd = "." };
    const argv = rt.gpa.alloc([]const u8, 3) catch return .{ .original = "zig test src/doctest.zig", .argv = &.{ "zig", "test", "src/doctest.zig" }, .cwd = "." };
    argv[0] = "zig";
    argv[1] = "test";
    argv[2] = rel;
    return .{ .original = original, .argv = argv, .cwd = "<project>" };
}

/// Real snippet runner for the mutation experiment: write the mutated snippet to
/// a content-addressed file under the zentinel cache and run `zig test` on it.
/// Confined to the cache dir, so the documentation file is never modified.
fn doctestMutateRunFn(ctx: *anyopaque, mutated_source: []const u8) zentinel.runner.RawOutcome {
    const rt: *DoctestMutateCtx = @ptrCast(@alignCast(ctx));
    const crash: zentinel.runner.RawOutcome = .{ .exit_code = null, .timed_out = false, .crashed = true, .duration_ms = 0, .stdout = "", .stderr = "" };
    const rel = doctestMutateRelPath(rt.gpa, mutated_source) orelse return crash;
    if (zentinel.config.pathEscapesRoot(rt.io, rt.root_dir, rel)) return crash;
    if (std.fs.path.dirname(rel)) |parent| rt.root_dir.createDirPath(rt.io, parent) catch return crash;
    rt.root_dir.writeFile(rt.io, .{ .sub_path = rel, .data = mutated_source }) catch return crash;
    const result = std.process.run(rt.gpa, rt.io, .{
        .argv = &.{ "zig", "test", rel },
        .cwd = .{ .dir = rt.root_dir },
        .stdout_limit = run_output_limit,
        .stderr_limit = run_output_limit,
        .timeout = rt.timeout,
        .environ_map = rt.env,
    }) catch |err| {
        if (err == error.Timeout) return .{ .exit_code = null, .timed_out = true, .crashed = false, .duration_ms = 0, .stdout = "", .stderr = "" };
        return crash;
    };
    return switch (result.term) {
        .exited => |code| .{ .exit_code = @as(i64, code), .timed_out = false, .crashed = false, .duration_ms = 0, .stdout = result.stdout, .stderr = result.stderr },
        else => .{ .exit_code = null, .timed_out = false, .crashed = true, .duration_ms = 0, .stdout = result.stdout, .stderr = result.stderr },
    };
}

fn runDoctestMutate(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    inv: zentinel.RunInvocation,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    parent_env: *const std.process.Environ.Map,
) !u8 {
    var file: ?[]const u8 = null;
    var i: usize = 0;
    while (i < inv.args.len) : (i += 1) {
        const arg = inv.args[i];
        if (std.mem.eql(u8, arg, "--mutate")) continue;
        if (std.mem.eql(u8, arg, "--file")) {
            i += 1;
            if (i >= inv.args.len) {
                try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --file requires a value\n");
                return 2;
            }
            file = inv.args[i];
        } else {
            try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: unsupported doctest --mutate option {s}\n", .{try zentinel.redactCliDiagnosticPath(gpa, arg)});
            return 2;
        }
    }

    const doc = file orelse {
        try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: doctest --mutate requires --file\n");
        return 2;
    };
    // Read-side path containment (F-5): reject an out-of-root --file.
    if (zentinel.config.isOutsideRoot(doc)) {
        try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --file must stay within the project root\n");
        return 2;
    }
    const cfg = (try doctestConfigOrDefault(gpa, io, dir, inv.globals, stderr)) orelse return 2;
    // Opt-in: passing `--mutate` explicitly is the opt-in (task 113 retired the
    // hardcoded fixtures-only gate, so it now runs over any --file documentation).

    const zig = discoverZig(gpa, io);
    const fatal_zig = try zentinel.zig_version.fatalStatusLine(gpa, zig);
    if (fatal_zig.len > 0) {
        try stderr.print("{s}\n", .{fatal_zig});
        return zentinel.zig_version.failureExit(zig);
    }

    var roots = (try openEffectiveProjectRoot(io, dir, inv.globals.root, cfg.project_root, stderr)) orelse return 2;
    defer roots.close(io);
    const root_dir = roots.dir();
    if (zentinel.config.pathEscapesRoot(io, root_dir, doc)) {
        try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: --file must stay within the project root\n");
        return 2;
    }
    const source = root_dir.readFileAlloc(io, doc, gpa, read_limit) catch {
        try stderr.print("error: documentation file not found at {s}\n", .{try zentinel.redactCliDiagnosticPath(gpa, doc)});
        return 2;
    };

    var minimal_env = try zentinel.runner.minimalEnviron(gpa, parent_env);
    defer minimal_env.deinit();

    var ctx = DoctestMutateCtx{
        .gpa = gpa,
        .io = io,
        .root_dir = root_dir,
        .timeout = timeoutFromMs(cfg.test_timeout_ms),
        .env = &minimal_env,
    };
    const sr = zentinel.doctest.mutation_experiment.SnippetRunner{ .ctx = &ctx, .runFn = doctestMutateRunFn, .commandFn = doctestMutateCommandFn };
    // Produce the STABLE mutation-aware report (durable `dm_` ids, `ds_` survivor
    // refs) and PERSIST it to the survivor report path so `doctest
    // explain-survivor` can resolve a real survivor (task 113).
    const json = try zentinel.doctest.mutation_experiment.mutateReportJson(gpa, doc, source, sr);
    const out_path = zentinel.ai.doctest_command.default_report_path;
    if (zentinel.config.pathEscapesRoot(io, root_dir, out_path)) {
        try stderr.writeAll("error: doctest mutation report path must stay within the project root\n");
        return 2;
    }
    if (std.fs.path.dirname(out_path)) |parent| root_dir.createDirPath(io, parent) catch {};
    root_dir.writeFile(io, .{ .sub_path = out_path, .data = json }) catch |err| {
        try stderr.print("error: could not write doctest mutation report to {s}: {s}\n", .{ out_path, @errorName(err) });
        return 2;
    };
    try stdout.writeAll(json);
    try stdout.writeAll("\n");
    // Surviving documentation mutants are reported but do not fail the command;
    // they are resolved advisorily via `doctest explain-survivor`.
    return 0;
}
