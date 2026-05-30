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
    const rel = try std.fmt.allocPrint(rt.gpa, ".zig-cache/zentinel/workspaces/{s}/{s}", .{ rt.run_id, m.id });
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
            error.InvalidReportFormat => "--report must be 'text' or 'json'",
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
        error.JobsNotSupported => {
            try stderr.writeAll("error: run.jobs > 1 is not supported yet (parallel execution lands in a later task)\n");
            return 2;
        },
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

    // Concise, survivor-focused stdout (or the JSON when explicitly requested).
    if (options.report_format == .json) {
        try stdout.writeAll(json);
        try stdout.writeAll("\n");
    } else {
        const summary = try zentinel.run_command.textSummary(gpa, outcome.report);
        try stdout.writeAll(summary);
    }
    return outcome.exit_code;
}
