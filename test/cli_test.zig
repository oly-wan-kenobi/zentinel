const std = @import("std");
const zentinel = @import("zentinel");

const cli_help_snapshot = @embedFile("snapshots/cli_help.txt");
const init_config_snapshot = @embedFile("snapshots/init_config.toml");

fn dispatch(args: []const []const u8, config_exists: bool) zentinel.Outcome {
    return zentinel.dispatch(args, config_exists);
}

test "help output matches the snapshot" {
    const out = dispatch(&[_][]const u8{"--help"}, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expectEqualStrings(cli_help_snapshot, out.stdout);
    try std.testing.expectEqualStrings(cli_help_snapshot, zentinel.help_text);
}

test "help lists the real doctest subcommands and report formats" {
    // Spec-drift cleanup (task 116): --help omitted the doctest AI/mutation
    // subcommands and the run report formats, so the help surface disagreed with
    // CLI_SPEC and the implemented CLI. Help must list every doctest subcommand
    // the binary actually accepts, the four run report formats, and doctest's
    // real --format set (text|json -- jsonl is NOT a doctest format).
    const h = dispatch(&[_][]const u8{"--help"}, false).stdout;
    for ([_][]const u8{
        "doctest explain",
        "doctest suggest",
        "doctest review-snapshot",
        "doctest suggest-missing",
        "doctest explain-survivor",
        "doctest --mutate",
    }) |sub| {
        try std.testing.expect(std.mem.indexOf(u8, h, sub) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, h, "run --report <text|json|jsonl|junit>") != null);
    try std.testing.expect(std.mem.indexOf(u8, h, "doctest --format <text|json>") != null);
}

test "version output is the policy-only composition" {
    const out = dispatch(&[_][]const u8{"version"}, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expectEqualStrings("zentinel 0.0.0\nzig 0.16.0\n", out.stdout);
}

test "version stays policy-only until task 005 owns Zig discovery" {
    // Boundary: task 001 prints the static pinned Zig policy label and must not
    // invoke `zig version` or own compatibility diagnostics; task 005 adds that.
    try std.testing.expectEqualStrings(
        "zentinel " ++ zentinel.version ++ "\nzig " ++ zentinel.supported_zig_version ++ "\n",
        zentinel.version_text,
    );
    try std.testing.expectEqualStrings("0.16.0", zentinel.supported_zig_version);
}

test "init refuses to overwrite an existing config without --force" {
    const out = dispatch(&[_][]const u8{"init"}, true);
    try std.testing.expectEqual(@as(u8, 2), out.exit_code);
    try std.testing.expect(!out.write_config);
    try std.testing.expect(std.mem.indexOf(u8, out.stderr, "--force") != null);
}

test "init --force overwrites an existing config with the default template" {
    const out = dispatch(&[_][]const u8{ "init", "--force" }, true);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expect(out.write_config);
    try std.testing.expectEqualStrings("created zentinel.toml\n", out.stdout);
}

test "init creates config when none exists" {
    const out = dispatch(&[_][]const u8{"init"}, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expect(out.write_config);
}

test "default config matches the snapshot" {
    try std.testing.expectEqualStrings(init_config_snapshot, zentinel.default_config);
}

test "route supersedes the removed not_implemented_commands list" {
    // task 116: the vestigial not_implemented_commands entries are removed.
    // run/check/list-mutants/doctest are real routed commands now, so route()
    // returns a concrete route for each and the frozen dispatch fallback no
    // longer mislabels any command as 'not implemented'. Before the cleanup,
    // dispatch("run") returned ZNTL_CLI_COMMAND_NOT_IMPLEMENTED.
    inline for (.{ "run", "check", "list-mutants", "doctest" }) |cmd| {
        try std.testing.expect(std.meta.activeTag(zentinel.route(&[_][]const u8{cmd})) != .passthrough);
        const out = dispatch(&[_][]const u8{cmd}, false);
        try std.testing.expect(out.error_code != .cli_command_not_implemented);
    }
}

test "unknown command returns ZNTL_CLI_UNKNOWN_COMMAND" {
    const out = dispatch(&[_][]const u8{"frobnicate"}, false);
    try std.testing.expectEqual(@as(u8, 2), out.exit_code);
    try std.testing.expect(out.error_code == .cli_unknown_command);
    try std.testing.expectEqualStrings("ZNTL_CLI_UNKNOWN_COMMAND", out.error_code.token());
    try std.testing.expectEqualStrings("frobnicate", out.detail);
}

test "--no-color parses before dispatch and keeps help byte-stable" {
    const out = dispatch(&[_][]const u8{ "--no-color", "--help" }, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expectEqualStrings(cli_help_snapshot, out.stdout);
}

test "config-aware init accepts --test-command (owned by task 002)" {
    const out = dispatch(&[_][]const u8{ "init", "--test-command", "zig build test" }, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expect(out.write_config);
    try std.testing.expect(out.init_test_command != null);
    try std.testing.expectEqualStrings("zig build test", out.init_test_command.?);
}

test "config-aware init accepts --backend ast" {
    const out = dispatch(&[_][]const u8{ "init", "--backend", "ast" }, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expect(out.write_config);
}

test "init rejects experimental --backend zir/air without enabling them" {
    const zir = dispatch(&[_][]const u8{ "init", "--backend", "zir" }, false);
    try std.testing.expectEqual(@as(u8, 2), zir.exit_code);
    try std.testing.expect(zir.error_code == .cli_invalid_option);
    try std.testing.expect(!zir.write_config);
    try std.testing.expectEqualStrings("zir", zir.detail);

    const air = dispatch(&[_][]const u8{ "init", "--backend", "air" }, false);
    try std.testing.expectEqual(@as(u8, 2), air.exit_code);
    try std.testing.expect(!air.write_config);
    try std.testing.expectEqualStrings("air", air.detail);
}

test "known future global option returns ZNTL_CLI_INVALID_OPTION before its owner task" {
    const out = dispatch(&[_][]const u8{ "--config", "zentinel.toml", "check" }, false);
    try std.testing.expectEqual(@as(u8, 2), out.exit_code);
    try std.testing.expect(out.error_code == .cli_invalid_option);
    try std.testing.expectEqualStrings("ZNTL_CLI_INVALID_OPTION", out.error_code.token());
    try std.testing.expectEqualStrings("--config", out.detail);
}
