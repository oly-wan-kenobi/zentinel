// Layer: deterministic_core
const std = @import("std");

/// Stable project name. Deterministic compile-time constant.
pub const project_name = "zentinel";

/// Initial project version. Deterministic compile-time constant.
pub const version = "0.0.0";

/// Zig version policy and discovery classification (deterministic core).
pub const zig_version = @import("zig_version.zig");

/// Pinned supported Zig version, owned by the single version-policy module
/// `zig_version`. `zentinel version` prints it as a policy label; `version` and
/// `check` compare real `zig version` discovery against this pin.
pub const supported_zig_version = zig_version.supported_version;

/// Config parsing and validation (deterministic core).
pub const config = @import("config.zig");
pub const config_toml = @import("config_toml.zig");

/// Shared shell-free command-string parser (deterministic core).
pub const command = @import("command.zig");

/// `zentinel check` orchestration (deterministic core).
pub const check_command = @import("check_command.zig");

/// Shared mutant model + durable `m_...` identity algorithm (deterministic core).
pub const mutant = @import("mutant.zig");

/// Safety/optimization mode matrix model + classification (deterministic core).
pub const safety_modes = @import("safety_modes.zig");

/// Deterministic seeded property-test generator + structural validator for the
/// `zentinel.pipeline.property_report.v1` contract (deterministic core, task
/// 062). The generator is a pure seeded stream; the validator distinguishes
/// passing property evidence from missing/malformed evidence. Neither uses AI.
pub const property = struct {
    pub const generator = @import("property/generator.zig");
    pub const report = @import("property/report.zig");
};

/// Pure byte <-> line/column source mapping (deterministic core).
pub const source_map = @import("source_map.zig");

/// Config-driven project model + source discovery (deterministic core).
pub const project_model = @import("project_model.zig");

/// AST parsing adapter over the pinned std.zig.Ast (deterministic core).
pub const ast_backend = @import("ast_backend.zig");

/// Experimental ZIR backend prototype (docs/ZIR_BACKEND.md). Opt-in only;
/// re-tags exactly-mapped AST candidates as experimental and records unsupported
/// operators as out-of-report diagnostics.
pub const zir_backend = @import("zir_backend.zig");

// The experimental AIR backend was retired: meaningful AIR-level mutation
// mapping is infeasible without Zig's SEMA stage, and the prototype only
// relabeled AST candidates. AST is the stable default; ZIR is the experimental
// lowered-IR backend.

/// AST mutators (deterministic core). Each recognizer emits candidates through
/// the shared collector; mutators may not import runner/sandbox/report/cli/ai.
pub const mutators = struct {
    pub const arithmetic = @import("mutators/arithmetic.zig");
    pub const comparison = @import("mutators/comparison.zig");
    pub const logical = @import("mutators/logical.zig");
    pub const boolean = @import("mutators/boolean.zig");
    pub const optional = @import("mutators/optional.zig");
    pub const error_path = @import("mutators/error_path.zig");
    pub const integer_boundary = @import("mutators/integer_boundary.zig");
    pub const loop_boundary = @import("mutators/loop_boundary.zig");
};

/// Deterministic patch sandbox: applies one mutant to a source copy (deterministic core).
pub const sandbox = @import("sandbox.zig");

/// Baseline runner: classifies test-command outcomes via an injected executor (deterministic core).
pub const runner = @import("runner.zig");

/// Mutant runner: runs one patched mutant and classifies the result (deterministic core).
pub const mutant_runner = @import("mutant_runner.zig");

/// Typed report model + deterministic JSON serialization (deterministic core).
pub const report = @import("report.zig");

/// `zentinel run` Phase 1 orchestration + report assembly (deterministic core).
pub const run_command = @import("run_command.zig");

/// Bounded parallel worker pool: deterministic index->result mapping and
/// content-addressed per-worker workspace isolation (deterministic core).
pub const worker_pool = @import("worker_pool.zig");

/// `zentinel list-mutants` candidate generation + rendering (deterministic core).
pub const list_mutants_command = @import("list_mutants_command.zig");

/// Same-file test selection + fallback (deterministic core).
pub const test_selection = @import("test_selection.zig");

/// Compiler-oracle semantic filter (deterministic core, ZIR_IMPROVEMENTS SEM-1c):
/// replaces the heuristic `expected_compile` prediction with the compiler's actual
/// verdict, derived from the mutant's terminal run status (the runner already
/// compiled it). SEM-1b's TCE equivalence half was descoped (0 measured payoff).
pub const semantic_filter = @import("semantic_filter.zig");

/// Shared error-code tokens (deterministic core).
pub const error_codes = @import("error_codes.zig");

/// Doctest Markdown fenced-block parser + block model + case extraction
/// (deterministic core).
pub const doctest = struct {
    pub const block = @import("doctest/block.zig");
    pub const parser = @import("doctest/parser.zig");
    pub const case = @import("doctest/case.zig");
    pub const extractor = @import("doctest/extractor.zig");
    pub const workspace = @import("doctest/workspace.zig");
    pub const runner = @import("doctest/runner.zig");
    pub const normalizer = @import("doctest/normalizer.zig");
    pub const matcher = @import("doctest/matcher.zig");
    pub const snapshot = @import("doctest/snapshot.zig");
    pub const report = @import("doctest/report.zig");
    pub const mutator_doctest = @import("doctest/mutator_doctest.zig");
    pub const cache = @import("doctest/cache.zig");
    pub const mutation_experiment = @import("doctest/mutation_experiment.zig");
    pub const mutation_id = @import("doctest/mutation_id.zig");
};

/// AI provider plumbing, context construction, and privacy redaction. AI is
/// advisory-only and never influences deterministic-core decisions.
pub const ai = struct {
    pub const provider = @import("ai/provider.zig");
    pub const context = @import("ai/context.zig");
    pub const redaction = @import("ai/redaction.zig");
    pub const command = @import("ai/command.zig");
    pub const doctest_command = @import("ai/doctest_command.zig");
};

/// `zentinel doctest` command orchestration (deterministic core).
pub const doctest_command = @import("doctest_command.zig");

/// Deterministic cache key construction + cache metadata (deterministic core).
pub const cache = @import("cache.zig");

/// Report renderers: survivor-focused text, streaming JSONL, and JUnit XML
/// (deterministic core). All derive from the canonical report.v1 model.
pub const report_text = @import("report_text.zig");
pub const report_jsonl = @import("report_jsonl.zig");
pub const report_junit = @import("report_junit.zig");

/// Whether a `--test-command` value can be safely embedded as a TOML basic-string
/// array element in zentinel.toml. zentinel's TOML reader (src/config_toml.zig)
/// has NO string escapes, so a value containing `"` would close the string early
/// and inject extra array elements (e.g. `zig test", "evil` -> two commands), and
/// a control byte (newline/tab/...) would malform the file. Such a value is
/// unrepresentable; `dispatchInit` rejects it rather than write an injected or
/// broken config. Backslash is read literally by the reader, so it is safe.
pub fn testCommandEmbeddable(value: []const u8) bool {
    for (value) |c| {
        if (c == '"' or c < 0x20 or c == 0x7f) return false;
    }
    return true;
}

/// Render the deterministic default `zentinel.toml`, optionally substituting the
/// baseline test command for config-aware `init --test-command`. Precondition:
/// `dispatchInit` has rejected any value that is not `testCommandEmbeddable`, so
/// the raw substitution stays a single quoted array element and is injection-safe
///.
pub fn initConfigText(arena: std.mem.Allocator, test_command: ?[]const u8) ![]const u8 {
    const cmd = test_command orelse return default_config;
    const needle = "commands = [\"zig build test\"]";
    const replacement = try std.fmt.allocPrint(arena, "commands = [\"{s}\"]", .{cmd});
    const size = std.mem.replacementSize(u8, default_config, needle, replacement);
    const out = try arena.alloc(u8, size);
    _ = std.mem.replace(u8, default_config, needle, replacement, out);
    return out;
}

/// Deterministic, snapshot-tested `--help` output. Mirrors test/snapshots/cli_help.txt.
pub const help_text =
    \\zentinel - Zig-native mutation testing
    \\
    \\Usage:
    \\  zentinel <command> [options]
    \\
    \\Commands:
    \\  init           create zentinel.toml
    \\  version        print version information
    \\  check          validate config and environment
    \\  list-mutants   list generated mutants without running tests
    \\  run            run mutation testing
    \\  doctest        validate executable documentation
    \\  explain        explain one mutant using advisory AI
    \\  suggest        suggest tests for one mutant using advisory AI
    \\  review-tests   review survivors using advisory AI
    \\
    \\Doctest subcommands (advisory AI is opt-in):
    \\  doctest explain <case-ref>            explain a failing doctest case
    \\  doctest suggest <doc-path>            suggest examples for a doc
    \\  doctest review-snapshot <case-ref>    review snapshot differences
    \\  doctest suggest-missing [--file ...]  list public docs needing examples
    \\  doctest explain-survivor <ref>        explain a mutation-aware survivor
    \\  doctest --mutate --file <doc-path>    run the mutation-aware doctest pass
    \\
    \\Report formats:
    \\  run --report <text|json|jsonl|junit>
    \\  doctest --format <text|json>
    \\
;

/// Deterministic `version` output: zentinel version plus pinned Zig policy label.
pub const version_text = "zentinel " ++ version ++ "\nzig " ++ supported_zig_version ++ "\n";

/// Deterministic default `zentinel.toml` template written by `init`.
/// Mirrors test/snapshots/init_config.toml and the full example in docs/CONFIG_SPEC.md.
pub const default_config =
    \\[project]
    \\name = "example"
    \\root = "."
    \\include = ["src/**/*.zig"]
    \\exclude = [".zig-cache/**", "zig-out/**", "test/**"]
    \\
    \\[zig]
    \\version = "0.16.0"
    \\modes = ["Debug"]
    \\
    \\[backend]
    \\default = "ast"
    \\experimental = []
    \\
    \\[mutators]
    \\enabled = [
    \\  "arithmetic_add_sub",
    \\  "arithmetic_mul_div",
    \\  "equality_swap",
    \\  "comparison_boundary",
    \\  "logical_and_or",
    \\  "boolean_literal"
    \\]
    \\
    \\[test]
    \\commands = ["zig build test"]
    \\selection = "same_file_then_package"
    \\timeout_ms = 30000
    \\baseline_required = true
    \\
    \\[run]
    \\jobs = 1
    \\
    \\[cache]
    \\enabled = true
    \\directory = ".zig-cache/zentinel"
    \\
    \\[report]
    \\formats = ["text", "json"]
    \\output_dir = "zig-out/zentinel"
    \\
    \\[ai]
    \\enabled = false
    \\provider = "disabled"
    \\remote_allowed = false
    \\source_context_lines = 4
    \\redact_patterns = ["(?i)api[_-]?key", "(?i)token"]
    \\
;

/// CLI usage error codes owned by the Phase 0 shell (docs/ERROR_CODES.md).
pub const ErrorCode = enum {
    none,
    cli_unknown_command,
    cli_command_not_implemented,
    cli_invalid_option,

    pub fn token(self: ErrorCode) []const u8 {
        return switch (self) {
            .none => "",
            .cli_unknown_command => "ZNTL_CLI_UNKNOWN_COMMAND",
            .cli_command_not_implemented => "ZNTL_CLI_COMMAND_NOT_IMPLEMENTED",
            .cli_invalid_option => "ZNTL_CLI_INVALID_OPTION",
        };
    }
};

/// Result of a pure CLI dispatch. The presentation adapter performs all I/O
/// (writing stdout/stderr and, when `write_config` is set, the config file).
pub const Outcome = struct {
    exit_code: u8 = 0,
    stdout: []const u8 = "",
    /// Static stderr text (used for messages without a dynamic name).
    stderr: []const u8 = "",
    error_code: ErrorCode = .none,
    /// Offending command or option name for coded errors; slices into `args`.
    detail: []const u8 = "",
    /// When true, the adapter writes the init config to zentinel.toml.
    write_config: bool = false,
    /// Baseline test command for config-aware `init --test-command`; null uses the default template.
    init_test_command: ?[]const u8 = null,
};

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn isOption(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "--");
}

/// Pure CLI dispatch. `args` excludes the program name. `config_exists` reflects
/// whether zentinel.toml already exists in the project root.
pub fn dispatch(args: []const []const u8, config_exists: bool) Outcome {
    var i: usize = 0;

    // Leading global options parse before command dispatch.
    while (i < args.len and isOption(args[i])) : (i += 1) {
        const opt = args[i];
        if (eq(opt, "--help") or eq(opt, "-h")) {
            return .{ .stdout = help_text };
        }
        if (eq(opt, "--no-color")) {
            // Accepted globally; non-colored output is unchanged.
            continue;
        }
        // Unknown options (including not-yet-owned global ones) are usage errors.
        return .{ .exit_code = 2, .error_code = .cli_invalid_option, .detail = opt };
    }

    if (i >= args.len) {
        // No command: show help.
        return .{ .stdout = help_text };
    }

    const cmd = args[i];
    i += 1;

    if (eq(cmd, "version")) {
        return .{ .stdout = version_text };
    }
    if (eq(cmd, "init")) {
        return dispatchInit(args[i..], config_exists);
    }
    // `check`/`list-mutants`/`run`/`doctest` and the AI commands are real routed
    // commands handled by `route`; they never reach this frozen fallback, so
    // dispatch no longer carries a vestigial "not implemented" roadmap list. Any
    // command that does reach here is genuinely unknown.
    return .{ .exit_code = 2, .error_code = .cli_unknown_command, .detail = cmd };
}

fn dispatchInit(rest: []const []const u8, config_exists: bool) Outcome {
    var force = false;
    var test_command: ?[]const u8 = null;
    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        const arg = rest[i];
        if (eq(arg, "--force")) {
            force = true;
        } else if (eq(arg, "--test-command")) {
            i += 1;
            if (i >= rest.len) return .{ .exit_code = 2, .error_code = .cli_invalid_option, .detail = "--test-command" };
            // Reject values that cannot be embedded in zentinel's escape-free TOML:
            // a `"` would inject extra commands, a control byte would malform the
            // file. Caught here so no "created zentinel.toml" is printed.
            if (!testCommandEmbeddable(rest[i])) return .{ .exit_code = 2, .error_code = .cli_invalid_option, .detail = "--test-command" };
            test_command = rest[i];
        } else if (eq(arg, "--backend")) {
            i += 1;
            if (i >= rest.len) return .{ .exit_code = 2, .error_code = .cli_invalid_option, .detail = "--backend" };
            const value = rest[i];
            // init only writes the stable AST backend; it never enables experimental backends.
            if (!eq(value, "ast")) return .{ .exit_code = 2, .error_code = .cli_invalid_option, .detail = value };
        } else {
            return .{ .exit_code = 2, .error_code = .cli_invalid_option, .detail = arg };
        }
    }

    if (config_exists and !force) {
        return .{
            .exit_code = 2,
            .stderr = "zentinel.toml already exists; use --force to overwrite\n",
        };
    }

    return .{ .stdout = "created zentinel.toml\n", .write_config = true, .init_test_command = test_command };
}

/// Default config file path when `--config` is not given.
pub const config_default_path = "zentinel.toml";

/// Parsed global options shared across project commands (docs/CLI_SPEC.md).
/// Shared by `check` and the other project commands.
pub const Globals = struct {
    config_path: []const u8 = config_default_path,
    config_explicit: bool = false,
    root: []const u8 = ".",
};

pub const ConfigPathError = error{ConfigOutsideRoot} || std.mem.Allocator.Error;

/// Resolve the config path relative to the selected project root. An explicit
/// `--config` is project-root-relative, not process-cwd-relative, so `--root x
/// --config zentinel.toml` reads `x/zentinel.toml`.
pub fn resolveConfigPathForRoot(arena: std.mem.Allocator, globals: Globals) ConfigPathError![]const u8 {
    if (globals.config_explicit and config.isOutsideRoot(globals.config_path)) return error.ConfigOutsideRoot;
    if (std.mem.eql(u8, globals.root, ".")) return arena.dupe(u8, globals.config_path);
    return std.fmt.allocPrint(arena, "{s}/{s}", .{ globals.root, globals.config_path });
}

/// The single stable cleanup-warning diagnostic format, shared by the allocating
/// `cleanupWarningText` and the streaming `emitCleanupWarningIfNeeded` so the two
/// surfaces cannot drift apart.
const cleanup_warning_fmt = "warning: failed to remove {d} mutation workspace(s)\n";

/// Stable cleanup warning surface shared by the CLI adapter and tests.
pub fn cleanupWarningText(arena: std.mem.Allocator, count: u32) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(arena, cleanup_warning_fmt, .{count});
}

/// Adapter-visible cleanup warning emission. A zero count is intentionally silent;
/// a non-zero count streams `cleanup_warning_fmt` directly. It needs no allocator
/// -- the prior signature accepted one only to discard it via `_ = arena;`.
pub fn emitCleanupWarningIfNeeded(count: u32, stderr: *std.Io.Writer) !void {
    if (count == 0) return;
    try stderr.print(cleanup_warning_fmt, .{count});
}

/// Redact user-supplied path values before echoing them in diagnostics that may
/// cross the same privacy boundary as advisory AI logs.
pub fn redactCliDiagnosticPath(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    var log = ai.context.RedactionLog.init(arena);
    return ai.context.redactField(arena, path, &ai.command.default_redact_patterns, &log);
}

/// What the presentation adapter should do with an argv. The pure Phase 0
/// `dispatch` above stays frozen for the commands it already owns; `route` adds
/// the task-005 surface (global options, `check`, and Zig-aware `version`)
/// without changing `dispatch`. `.passthrough` means the adapter falls back to
/// `dispatch`, which still rejects options it does not own.
/// A `run` invocation: parsed globals plus the run-specific argv that follows
/// the `run` command (parsed by the run command, not the frozen dispatch).
pub const RunInvocation = struct {
    globals: Globals,
    args: []const []const u8,
};

pub const Route = union(enum) {
    passthrough,
    version,
    check: Globals,
    run: RunInvocation,
    list_mutants: RunInvocation,
    doctest: RunInvocation,
    explain: RunInvocation,
    suggest: RunInvocation,
    review_tests: RunInvocation,
};

/// Decide how to handle argv. `check` and `version` need environment inputs
/// (config bytes, discovered Zig) that only the adapter can gather, so routing
/// is kept separate from the pure `dispatch`. Global options `--config`/`--root`
/// are consumed only for the commands that own them; anything else passes
/// through to the frozen Phase 0 dispatch.
pub fn route(args: []const []const u8) Route {
    var globals: Globals = .{};
    var i: usize = 0;
    while (i < args.len and isOption(args[i])) {
        const opt = args[i];
        if (eq(opt, "--help") or eq(opt, "-h")) return .passthrough;
        if (eq(opt, "--no-color")) {
            i += 1;
            continue;
        }
        if (eq(opt, "--config")) {
            if (i + 1 >= args.len) return .passthrough; // missing value: dispatch reports it
            globals.config_path = args[i + 1];
            globals.config_explicit = true;
            i += 2;
            continue;
        }
        if (eq(opt, "--root")) {
            if (i + 1 >= args.len) return .passthrough;
            globals.root = args[i + 1];
            i += 2;
            continue;
        }
        // Unowned or unknown option: the frozen dispatch rejects it.
        return .passthrough;
    }

    if (i >= args.len) return .passthrough; // no command -> dispatch prints help

    const cmd = args[i];
    if (eq(cmd, "check")) return .{ .check = globals };
    if (eq(cmd, "run")) return .{ .run = .{ .globals = globals, .args = args[i + 1 ..] } };
    if (eq(cmd, "list-mutants")) return .{ .list_mutants = .{ .globals = globals, .args = args[i + 1 ..] } };
    if (eq(cmd, "doctest")) return .{ .doctest = .{ .globals = globals, .args = args[i + 1 ..] } };
    if (eq(cmd, "explain")) return .{ .explain = .{ .globals = globals, .args = args[i + 1 ..] } };
    if (eq(cmd, "suggest")) return .{ .suggest = .{ .globals = globals, .args = args[i + 1 ..] } };
    if (eq(cmd, "review-tests")) return .{ .review_tests = .{ .globals = globals, .args = args[i + 1 ..] } };
    if (eq(cmd, "version")) {
        // `version` does not own --config/--root; defer to dispatch when present.
        if (globals.config_explicit or !eq(globals.root, ".")) return .passthrough;
        return .version;
    }
    return .passthrough;
}

/// Read-side path containment (audit F-5): a user-supplied `--input-report` or
/// `--file` value that escapes the project root (an absolute path or a `..`
/// segment) is rejected so the read paths honor the same root-containment
/// contract as the write-side `--output` guard (`config.isOutsideRoot`). Returns
/// the offending option name for a clear usage error, or null when every read
/// path in `args` stays within the project root. Pure; reads no filesystem.
pub fn readPathOutsideRootOption(args: []const []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if ((eq(a, "--input-report") or eq(a, "--file")) and i + 1 < args.len) {
            if (config.isOutsideRoot(args[i + 1])) return a;
        }
    }
    return null;
}

test "project name is the stable constant" {
    try std.testing.expectEqualStrings("zentinel", project_name);
}

test "version is non-empty" {
    try std.testing.expect(version.len > 0);
}
