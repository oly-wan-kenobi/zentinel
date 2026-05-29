// Layer: deterministic_core
const std = @import("std");

/// Stable project name. Deterministic compile-time constant.
pub const project_name = "zentinel";

/// Initial project version. Deterministic compile-time constant.
pub const version = "0.0.0";

/// Pinned supported Zig version policy label. Task 001 prints this as a static
/// policy label only; task 005 owns real `zig version` discovery and
/// compatibility diagnostics. Task 001 must not invoke `zig version`.
pub const supported_zig_version = "0.16.0";

/// Config parsing and validation (deterministic core).
pub const config = @import("config.zig");
pub const config_toml = @import("config_toml.zig");

/// Render the deterministic default `zentinel.toml`, optionally substituting the
/// baseline test command for config-aware `init --test-command`.
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

/// Roadmap commands recognized but not implemented by the Phase 0 CLI shell.
const not_implemented_commands = [_][]const u8{
    "check",
    "list-mutants",
    "run",
    "doctest",
    "explain",
    "suggest",
    "review-tests",
};

/// Known future global options not owned by task 001 (rejected until their owner lands).
const future_global_options = [_][]const u8{
    "--config",
    "--root",
    "--verbose",
    "--quiet",
};

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn isOption(s: []const u8) bool {
    return std.mem.startsWith(u8, s, "--");
}

fn contains(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |item| {
        if (eq(item, needle)) return true;
    }
    return false;
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
        // Known future global options and unknown options are usage errors.
        return .{ .exit_code = 2, .error_code = .cli_invalid_option, .detail = opt };
    }

    if (i >= args.len) {
        // No command: show help.
        return .{ .stdout = help_text };
    }

    const command = args[i];
    i += 1;

    if (eq(command, "version")) {
        return .{ .stdout = version_text };
    }
    if (eq(command, "init")) {
        return dispatchInit(args[i..], config_exists);
    }
    if (contains(&not_implemented_commands, command)) {
        return .{ .exit_code = 2, .error_code = .cli_command_not_implemented, .detail = command };
    }
    return .{ .exit_code = 2, .error_code = .cli_unknown_command, .detail = command };
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

test "project name is the stable constant" {
    try std.testing.expectEqualStrings("zentinel", project_name);
}

test "version is non-empty" {
    try std.testing.expect(version.len > 0);
}
