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
            const resolved = try resolveConfigPath(gpa, globals);
            const result = try zentinel.check_command.run(gpa, .{
                .config_source = readConfig(gpa, io, dir, resolved),
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
        .run => |inv| return runRun(gpa, io, dir, inv, stdout, stderr),
        .list_mutants => |inv| return runListMutants(gpa, io, dir, inv, stdout, stderr),
        .doctest => |inv| return runDoctest(gpa, io, dir, inv, stdout, stderr),
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
        const text = try zentinel.initConfigText(gpa, outcome.init_test_command);
        try dir.writeFile(io, .{ .sub_path = config_path, .data = text });
    }

    return outcome.exit_code;
}

/// Resolve the config path: an explicit `--config` wins; otherwise the default
/// config name is looked up under `--root` (default `.`).
fn resolveConfigPath(gpa: std.mem.Allocator, globals: zentinel.Globals) ![]const u8 {
    if (globals.config_explicit) return globals.config_path;
    if (std.mem.eql(u8, globals.root, ".")) return globals.config_path;
    return std.fmt.allocPrint(gpa, "{s}/{s}", .{ globals.root, globals.config_path });
}

fn readConfig(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) ?[]const u8 {
    return dir.readFileAlloc(io, path, gpa, read_limit) catch null;
}

/// Run `zig version` and classify the result. Any failure to obtain a version
/// (executable missing, non-zero exit, empty output) is reported as not found.
fn discoverZig(gpa: std.mem.Allocator, io: std.Io) zentinel.zig_version.Discovery {
    const result = std.process.run(gpa, io, .{ .argv = &.{ "zig", "version" } }) catch return .not_found;
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
        // Phase 1 inherits the developer environment and never uses a shell
        // (docs/SANDBOX_SECURITY.md: cannot fully sandbox in Phase 1). The
        // environment-policy label remains the documented intent.
        .environ_map = null,
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

fn copyExcluded(path: []const u8) bool {
    return std.mem.startsWith(u8, path, ".zig-cache") or
        std.mem.startsWith(u8, path, "zig-out") or
        std.mem.startsWith(u8, path, ".git");
}

const Workspace = struct { rel: []const u8, dir: std.Io.Dir };

/// Build an isolated per-mutant workspace under the zentinel-controlled cache
/// location: copy the project tree (minus caches/VCS), then overwrite the
/// mutated file with the patched bytes. Isolated by run + content-addressed
/// mutant id, so the developer working tree is never modified.
fn setupWorkspace(rt: *RunCtx, m: zentinel.mutant.Mutant, patched: []const u8) !Workspace {
    // Content-addressed, per-mutant root so concurrent workers never share a
    // writable workspace, local .zig-cache, or zig-out (tasks/050).
    const rel = try zentinel.worker_pool.workspaceRoot(rt.gpa, rt.run_id, m.id);
    try rt.root_dir.createDirPath(rt.io, rel);
    var dir = try rt.root_dir.openDir(rt.io, rel, .{});
    errdefer dir.close(rt.io);

    var walker = try rt.root_dir.walk(rt.gpa);
    defer walker.deinit();
    while (try walker.next(rt.io)) |entry| {
        if (entry.kind != .file) continue;
        if (copyExcluded(entry.path)) continue;
        rt.root_dir.copyFile(entry.path, dir, entry.path, rt.io, .{ .make_path = true }) catch continue;
    }
    try dir.writeFile(rt.io, .{ .sub_path = m.file, .data = patched });
    return .{ .rel = rel, .dir = dir };
}

fn mutantRunFn(
    ctx: *anyopaque,
    m: zentinel.mutant.Mutant,
    source: []const u8,
    commands: []const []const u8,
    mode: zentinel.report.Mode,
) zentinel.mutant_runner.MutationResult {
    const rt: *RunCtx = @ptrCast(@alignCast(ctx));
    const disabled = zentinel.runner.Executor{ .ctx = rt, .runFn = unusedRunFn };

    // Compute patched bytes up front; an invalid patch is classified by the
    // deterministic runner (which re-validates and returns without executing).
    const patched = zentinel.sandbox.apply(rt.gpa, source, m) catch {
        return zentinel.mutant_runner.run(rt.gpa, m, source, .created, commands, rt.root_label, disabled, mode) catch @panic("out of memory");
    };
    const ws = setupWorkspace(rt, m, patched) catch {
        return zentinel.mutant_runner.run(rt.gpa, m, source, .create_failed, commands, rt.root_label, disabled, mode) catch @panic("out of memory");
    };
    defer {
        ws.dir.close(rt.io);
        rt.root_dir.deleteTree(rt.io, ws.rel) catch {};
    }
    var wctx = WorkspaceCtx{ .rt = rt, .dir = ws.dir };
    const executor = zentinel.runner.Executor{ .ctx = &wctx, .runFn = workspaceRunFn };
    return zentinel.mutant_runner.run(rt.gpa, m, source, .created, commands, rt.root_label, executor, mode) catch @panic("out of memory");
}

/// Build the run observation metadata (run id, ISO timestamp, config hash).
fn buildObservation(gpa: std.mem.Allocator, io: std.Io, cfg_bytes: []const u8, zig: zentinel.zig_version.Discovery, root_label: []const u8) !zentinel.run_command.Observation {
    const ts = std.Io.Timestamp.now(io, .real).toMilliseconds();
    const run_id = try std.fmt.allocPrint(gpa, "run_{x}", .{@as(u64, @intCast(@max(0, ts)))});

    const secs: u64 = @intCast(@max(0, @divTrunc(ts, 1000)));
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const ed = es.getEpochDay();
    const yd = ed.calculateYearDay();
    const md = yd.calculateMonthDay();
    const day = es.getDaySeconds();
    const started_at = try std.fmt.allocPrint(gpa, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year, md.month.numeric(), md.day_index + 1, day.getHoursIntoDay(), day.getMinutesIntoHour(), day.getSecondsIntoMinute(),
    });

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cfg_bytes, &digest, .{});
    const config_hash = try std.fmt.allocPrint(gpa, "sha256:{s}", .{std.fmt.bytesToHex(digest[0..8], .lower)});

    const zig_label: []const u8 = switch (zig) {
        .version => |v| v,
        .not_found => zentinel.supported_zig_version,
    };

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
) !u8 {
    const options = zentinel.run_command.parseArgs(inv.args) catch |err| {
        const detail = switch (err) {
            error.MissingValue => "missing option value",
            error.UnknownOption => "unknown run option",
            error.InvalidReportFormat => "--report must be text, json, jsonl, or junit",
            error.InvalidJobs => "--jobs must be a positive integer",
        };
        try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: {s}\n", .{detail});
        return 2;
    };

    const cfg_path = try resolveConfigPath(gpa, inv.globals);
    const cfg_bytes = readConfig(gpa, io, dir, cfg_path) orelse {
        try stderr.print("error: config not found at {s}\n", .{cfg_path});
        return 2;
    };
    var diag: zentinel.config.Diagnostic = .{};
    const cfg = zentinel.config.load(gpa, cfg_bytes, &diag) catch {
        try stderr.print("error[{s}]: {s}\n", .{ diag.code.token(), diag.message });
        return 2;
    };

    // Zig version is validated but non-fatal (mirrors `version`): a mismatch is
    // surfaced on stderr without blocking the run.
    const zig = discoverZig(gpa, io);
    if (try zentinel.zig_version.statusLine(gpa, zig)) |line| {
        try stderr.print("{s}\n", .{line});
    }

    var root_dir = try dir.openDir(io, inv.globals.root, .{ .iterate = true });
    defer root_dir.close(io);

    const discovered = try zentinel.project_model.discover(gpa, io, root_dir, cfg.include, cfg.exclude);
    var files: std.ArrayList(zentinel.run_command.FileSource) = .empty;
    for (discovered) |rel| {
        const bytes = root_dir.readFileAlloc(io, rel, gpa, read_limit) catch continue;
        try files.append(gpa, .{ .path = rel, .source = bytes });
    }

    const obs = try buildObservation(gpa, io, cfg_bytes, zig, inv.globals.root);

    var rt = RunCtx{
        .gpa = gpa,
        .io = io,
        .root_dir = root_dir,
        .root_label = inv.globals.root,
        .run_id = obs.run_id,
        .timeout = timeoutFromMs(cfg.test_timeout_ms),
    };
    const baseline_executor = zentinel.runner.Executor{ .ctx = &rt, .runFn = baselineRunFn };
    const mutant_executor = zentinel.run_command.MutantRunner{ .ctx = &rt, .runFn = mutantRunFn };

    const outcome = zentinel.run_command.run(gpa, cfg, files.items, options, baseline_executor, mutant_executor, obs) catch |err| switch (err) {
        error.OutputOutsideRoot => {
            try stderr.writeAll("error: --output must stay within the project root\n");
            return 2;
        },
        error.OutOfMemory => return err,
    };

    // Write the JSON report to the resolved output path (under the project root).
    const json = try zentinel.report.toJson(gpa, outcome.report);
    const out_path = options.output orelse try std.fmt.allocPrint(gpa, "{s}/report.json", .{cfg.report_output_dir});
    if (std.fs.path.dirname(out_path)) |parent| {
        root_dir.createDirPath(io, parent) catch {};
    }
    root_dir.writeFile(io, .{ .sub_path = out_path, .data = json }) catch |err| {
        try stderr.print("error: could not write report to {s}: {s}\n", .{ out_path, @errorName(err) });
        return 2;
    };

    // Emit deterministic cache metadata alongside the report (best-effort).
    const cache_json = try zentinel.cache.toJson(gpa, outcome.cache);
    const cache_path = try std.fmt.allocPrint(gpa, "{s}/cache.json", .{cfg.report_output_dir});
    if (std.fs.path.dirname(cache_path)) |parent| root_dir.createDirPath(io, parent) catch {};
    root_dir.writeFile(io, .{ .sub_path = cache_path, .data = cache_json }) catch {};

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
            error.InvalidFormat => "--format must be 'text' or 'json'",
        };
        try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: {s}\n", .{detail});
        return 2;
    };

    const cfg_path = try resolveConfigPath(gpa, inv.globals);
    const cfg_bytes = readConfig(gpa, io, dir, cfg_path) orelse {
        try stderr.print("error: config not found at {s}\n", .{cfg_path});
        return 2;
    };
    var diag: zentinel.config.Diagnostic = .{};
    const cfg = zentinel.config.load(gpa, cfg_bytes, &diag) catch {
        try stderr.print("error[{s}]: {s}\n", .{ diag.code.token(), diag.message });
        return 2;
    };

    var root_dir = try dir.openDir(io, inv.globals.root, .{ .iterate = true });
    defer root_dir.close(io);

    const discovered = try zentinel.project_model.discover(gpa, io, root_dir, cfg.include, cfg.exclude);
    var files: std.ArrayList(zentinel.list_mutants_command.FileSource) = .empty;
    for (discovered) |rel| {
        const bytes = root_dir.readFileAlloc(io, rel, gpa, read_limit) catch continue;
        try files.append(gpa, .{ .path = rel, .source = bytes });
    }

    const candidates = try zentinel.list_mutants_command.generate(gpa, cfg, files.items, options.operator_filter);

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
            try stderr.print("note[{s}]: {s} at {s}:{d}..{d} ({s})\n", .{ d.code, d.operator, d.file, d.span_start, d.span_end, d.reason });
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
            try stderr.print("note[{s}]: {s} at {s}:{d}..{d} source_mapping={s} mode={s} ({s})\n", .{ d.code, d.operator, d.file, d.span_start, d.span_end, d.source_mapping, d.safety_mode, d.reason });
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
        .environ_map = null,
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
    w.root_dir.createDirPath(w.io, plan.dir) catch return error.WorkspaceCreateFailed;
    for (plan.files) |f| {
        if (std.fs.path.dirname(f.rel_path)) |parent| {
            w.root_dir.createDirPath(w.io, parent) catch return error.WorkspaceCreateFailed;
        }
        w.root_dir.writeFile(w.io, .{ .sub_path = f.rel_path, .data = f.contents }) catch return error.WorkspaceCreateFailed;
    }
}

fn isoTimestamp(gpa: std.mem.Allocator, ms: i64) ![]const u8 {
    const secs: u64 = @intCast(@max(0, @divTrunc(ms, 1000)));
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const day = es.getDaySeconds();
    return std.fmt.allocPrint(gpa, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year, md.month.numeric(), md.day_index + 1, day.getHoursIntoDay(), day.getMinutesIntoHour(), day.getSecondsIntoMinute(),
    });
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
    var provider_override: ?zentinel.ai.command.Mode = null;
    var input_report: ?[]const u8 = null;
    var format: zentinel.ai.command.Format = .text;

    var i: usize = 0;
    while (i < inv.args.len) : (i += 1) {
        const a = inv.args[i];
        if (std.mem.eql(u8, a, "--ai-provider")) {
            i += 1;
            if (i >= inv.args.len) return aiOptionError(stderr, "--ai-provider requires a value");
            provider_override = zentinel.ai.provider.modeFromName(inv.args[i]) orelse
                return aiOptionError(stderr, "--ai-provider must be disabled|stub|local|remote");
        } else if (std.mem.eql(u8, a, "--input-report")) {
            i += 1;
            if (i >= inv.args.len) return aiOptionError(stderr, "--input-report requires a value");
            input_report = inv.args[i];
        } else if (std.mem.eql(u8, a, "--format")) {
            i += 1;
            if (i >= inv.args.len) return aiOptionError(stderr, "--format requires a value");
            if (std.mem.eql(u8, inv.args[i], "text")) {
                format = .text;
            } else if (std.mem.eql(u8, inv.args[i], "json")) {
                format = .json;
            } else return aiOptionError(stderr, "--format must be 'text' or 'json'");
        } else if (std.mem.startsWith(u8, a, "--")) {
            return aiOptionError(stderr, "unknown AI command option");
        } else if (flow != .review_tests and mutant_ref == null) {
            mutant_ref = a;
        } else {
            return aiOptionError(stderr, "unexpected positional argument");
        }
    }
    if (flow != .review_tests and mutant_ref == null) {
        return aiOptionError(stderr, "missing <mutant-ref>");
    }

    const settings = aiSettings(arena, gpa, io, dir, inv.globals);

    var root_dir = try dir.openDir(io, inv.globals.root, .{ .iterate = true });
    defer root_dir.close(io);
    const report_path = input_report orelse zentinel.ai.command.default_report_path;
    const report_json: ?[]const u8 = root_dir.readFileAlloc(io, report_path, arena, read_limit) catch null;

    const input = zentinel.ai.command.Input{
        .flow = flow,
        .mutant_ref = mutant_ref,
        .provider_override = provider_override,
        .report_json = report_json,
        .settings = settings,
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

/// Build advisory AI settings from normalized config, falling back to AI-disabled
/// defaults when no config file is present or it cannot be parsed.
fn aiSettings(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    globals: zentinel.Globals,
) zentinel.ai.command.Settings {
    const zig_label: []const u8 = switch (discoverZig(gpa, io)) {
        .version => |v| v,
        .not_found => zentinel.supported_zig_version,
    };
    var settings = zentinel.ai.command.Settings{
        .ai_enabled = false,
        .config_mode = .disabled,
        .remote_allowed = false,
        .redact_patterns = &zentinel.ai.command.default_redact_patterns,
        .project_name = zentinel.project_name,
        .zig_version = zig_label,
        .zentinel_version = zentinel.version,
    };
    const resolved = resolveConfigPath(arena, globals) catch return settings;
    const bytes = readConfig(arena, io, dir, resolved) orelse return settings;
    var diag: zentinel.config.Diagnostic = .{};
    const cfg = zentinel.config.load(arena, bytes, &diag) catch return settings;
    settings.ai_enabled = cfg.ai_enabled;
    settings.config_mode = zentinel.ai.provider.modeFromName(cfg.ai_provider) orelse .disabled;
    settings.remote_allowed = cfg.ai_remote_allowed;
    settings.redact_patterns = cfg.ai_redact_patterns;
    return settings;
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
    var input_report: ?[]const u8 = null;
    var provider_override: ?zentinel.ai.command.Mode = null;
    var format: zentinel.ai.command.Format = .text;

    var i: usize = 1; // skip the subcommand token at inv.args[0]
    while (i < inv.args.len) : (i += 1) {
        const a = inv.args[i];
        if (std.mem.eql(u8, a, "--ai-provider")) {
            i += 1;
            if (i >= inv.args.len) return aiOptionError(stderr, "--ai-provider requires a value");
            provider_override = zentinel.ai.provider.modeFromName(inv.args[i]) orelse
                return aiOptionError(stderr, "--ai-provider must be disabled|stub|local|remote");
        } else if (std.mem.eql(u8, a, "--input-report")) {
            i += 1;
            if (i >= inv.args.len) return aiOptionError(stderr, "--input-report requires a value");
            input_report = inv.args[i];
        } else if (std.mem.eql(u8, a, "--file")) {
            i += 1;
            if (i >= inv.args.len) return aiOptionError(stderr, "--file requires a value");
            file_opt = inv.args[i];
        } else if (std.mem.eql(u8, a, "--format")) {
            i += 1;
            if (i >= inv.args.len) return aiOptionError(stderr, "--format requires a value");
            if (std.mem.eql(u8, inv.args[i], "text")) {
                format = .text;
            } else if (std.mem.eql(u8, inv.args[i], "json")) {
                format = .json;
            } else return aiOptionError(stderr, "--format must be 'text' or 'json'");
        } else if (std.mem.startsWith(u8, a, "--")) {
            return aiOptionError(stderr, "unknown doctest AI option");
        } else if (positional == null) {
            positional = a;
        } else {
            return aiOptionError(stderr, "unexpected positional argument");
        }
    }

    const flow_is_case = (flow == .explain_doctest_failure or flow == .review_snapshot);
    const doc_path: ?[]const u8 = switch (flow) {
        .suggest_doctest => positional,
        .suggest_missing_doctests => file_opt,
        else => null,
    };
    const case_ref: ?[]const u8 = if (flow_is_case) positional else null;

    const settings = aiSettings(arena, gpa, io, dir, inv.globals);

    var root_dir = try dir.openDir(io, inv.globals.root, .{ .iterate = true });
    defer root_dir.close(io);

    const doc_exists = blk: {
        const d = doc_path orelse break :blk false;
        root_dir.access(io, d, .{}) catch break :blk false;
        break :blk true;
    };
    const report_json: ?[]const u8 = blk: {
        if (flow_is_case) {
            const rp = input_report orelse zentinel.ai.doctest_command.default_report_path;
            break :blk root_dir.readFileAlloc(io, rp, arena, read_limit) catch null;
        } else if (input_report) |rp| {
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
        .settings = settings,
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
) !u8 {
    // Experimental opt-in: `zentinel doctest --mutate` runs the mutation-aware
    // doctest prototype over fixture docs only (task 039).
    for (inv.args) |arg| {
        if (std.mem.eql(u8, arg, "--mutate")) return runDoctestMutate(gpa, io, dir, inv, stdout, stderr);
    }

    // Advisory doctest-AI subcommands (task 055): explain/suggest/review-snapshot/
    // suggest-missing. explain-survivor is reserved for task 067.
    if (inv.args.len > 0 and !std.mem.startsWith(u8, inv.args[0], "-")) {
        const sub = inv.args[0];
        if (std.mem.eql(u8, sub, "explain")) return runDoctestAi(gpa, io, dir, inv, .explain_doctest_failure, stdout, stderr);
        if (std.mem.eql(u8, sub, "suggest")) return runDoctestAi(gpa, io, dir, inv, .suggest_doctest, stdout, stderr);
        if (std.mem.eql(u8, sub, "review-snapshot")) return runDoctestAi(gpa, io, dir, inv, .review_snapshot, stdout, stderr);
        if (std.mem.eql(u8, sub, "suggest-missing")) return runDoctestAi(gpa, io, dir, inv, .suggest_missing_doctests, stdout, stderr);
        if (std.mem.eql(u8, sub, "explain-survivor")) {
            try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: doctest explain-survivor is owned by task 067 and not implemented yet\n", .{});
            return 2;
        }
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

    var root_dir = try dir.openDir(io, inv.globals.root, .{ .iterate = true });
    defer root_dir.close(io);

    const source = root_dir.readFileAlloc(io, doc_file, gpa, read_limit) catch {
        try stderr.print("error: documentation file not found at {s}\n", .{doc_file});
        return 2;
    };

    const zig = discoverZig(gpa, io);
    const zig_label: []const u8 = switch (zig) {
        .version => |v| v,
        .not_found => zentinel.supported_zig_version,
    };

    const ts = std.Io.Timestamp.now(io, .real).toMilliseconds();
    const run_id = try std.fmt.allocPrint(gpa, "doctest_run_{x}", .{@as(u64, @intCast(@max(0, ts)))});
    const started_at = try isoTimestamp(gpa, ts);
    const fmt_label: []const u8 = switch (options.format) {
        .text => "text",
        .json => "json",
    };
    const command = try std.fmt.allocPrint(gpa, "zentinel doctest --file {s} --format {s}", .{ doc_file, fmt_label });

    var dctx = DoctestCtx{ .gpa = gpa, .io = io, .root_dir = root_dir, .timeout = .none };
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
        .project_root = inv.globals.root,
        .command = command,
    };

    const out = zentinel.doctest_command.run(gpa, options, doc_file, source, obs, deps) catch |err| switch (err) {
        error.CaseNotFound => {
            try stderr.print("error[ZNTL_DOCTEST_CASE_NOT_FOUND]: --case did not resolve to exactly one case\n", .{});
            return 2;
        },
        error.WorkspaceCreateFailed => {
            try stderr.writeAll("error: could not create doctest workspace\n");
            return 4;
        },
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
};

/// Real snippet runner for the mutation experiment: write the mutated snippet to
/// a content-addressed file under the zentinel cache and run `zig test` on it.
/// Confined to the cache dir, so the documentation file is never modified.
fn doctestMutateRunFn(ctx: *anyopaque, mutated_source: []const u8) zentinel.runner.RawOutcome {
    const rt: *DoctestMutateCtx = @ptrCast(@alignCast(ctx));
    const crash: zentinel.runner.RawOutcome = .{ .exit_code = null, .timed_out = false, .crashed = true, .duration_ms = 0, .stdout = "", .stderr = "" };
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(mutated_source, &digest, .{});
    const rel = std.fmt.allocPrint(rt.gpa, ".zig-cache/zentinel/doctest-mutate/{s}.zig", .{std.fmt.bytesToHex(digest[0..8], .lower)}) catch return crash;
    if (std.fs.path.dirname(rel)) |parent| rt.root_dir.createDirPath(rt.io, parent) catch return crash;
    rt.root_dir.writeFile(rt.io, .{ .sub_path = rel, .data = mutated_source }) catch return crash;
    const result = std.process.run(rt.gpa, rt.io, .{
        .argv = &.{ "zig", "test", rel },
        .cwd = .{ .dir = rt.root_dir },
        .stdout_limit = run_output_limit,
        .stderr_limit = run_output_limit,
        .timeout = rt.timeout,
        .environ_map = null,
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
            try stderr.print("error[ZNTL_CLI_INVALID_OPTION]: unsupported doctest --mutate option {s}\n", .{arg});
            return 2;
        }
    }

    const doc = file orelse {
        try stderr.writeAll("error[ZNTL_CLI_INVALID_OPTION]: doctest --mutate requires --file\n");
        return 2;
    };
    // Experimental and opt-in: only run over fixture documentation.
    if (std.mem.indexOf(u8, doc, "fixtures/doctest") == null) {
        try stderr.writeAll("error: doctest --mutate is experimental and only runs over fixture docs (test/fixtures/doctest/**)\n");
        return 2;
    }

    var root_dir = try dir.openDir(io, inv.globals.root, .{ .iterate = true });
    defer root_dir.close(io);
    const source = root_dir.readFileAlloc(io, doc, gpa, read_limit) catch {
        try stderr.print("error: documentation file not found at {s}\n", .{doc});
        return 2;
    };

    var ctx = DoctestMutateCtx{ .gpa = gpa, .io = io, .root_dir = root_dir, .timeout = .none };
    const sr = zentinel.doctest.mutation_experiment.SnippetRunner{ .ctx = &ctx, .runFn = doctestMutateRunFn };
    const r = try zentinel.doctest.mutation_experiment.run(gpa, doc, source, sr);
    const json = try zentinel.doctest.mutation_experiment.toJson(gpa, r);
    try stdout.writeAll(json);
    try stdout.writeAll("\n");
    // Experimental prototype: surviving documentation mutants are reported but do
    // not fail the command (stabilization is a later task).
    return 0;
}
