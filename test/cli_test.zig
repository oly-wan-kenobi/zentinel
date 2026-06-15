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
    // Spec-drift cleanup: --help omitted the doctest AI/mutation
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
    // Derived from the version/zig-policy constants, not a hard-coded literal, so a
    // version bump cannot silently leave this assertion asserting a stale string.
    try std.testing.expectEqualStrings(
        "zentinel " ++ zentinel.version ++ "\nzig " ++ zentinel.supported_zig_version ++ "\n",
        out.stdout,
    );
}

test "version prints the pinned policy label without invoking zig" {
    // Boundary: `version` prints the static pinned Zig policy label and must not
    // invoke `zig version` or own compatibility diagnostics; `check` owns that.
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
    // The vestigial not_implemented_commands entries are removed.
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

test "config-aware init accepts --test-command" {
    const out = dispatch(&[_][]const u8{ "init", "--test-command", "zig build test" }, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expect(out.write_config);
    try std.testing.expect(out.init_test_command != null);
    try std.testing.expectEqualStrings("zig build test", out.init_test_command.?);
}

test "config-aware init rejects a --test-command that would inject TOML structure" {
    // zentinel's TOML reader has no string escapes, so a `"` in --test-command
    // would close the string and inject a SECOND array element (silently adding a
    // command). The value is rejected with exit 2 and NO config is written.
    const out = dispatch(&[_][]const u8{ "init", "--force", "--test-command", "zig test\", \"evil" }, false);
    try std.testing.expectEqual(@as(u8, 2), out.exit_code);
    try std.testing.expect(out.error_code == .cli_invalid_option);
    try std.testing.expect(!out.write_config);
    try std.testing.expect(out.init_test_command == null);
    // A control byte (e.g. a newline) would also malform the file -> rejected.
    const nl = dispatch(&[_][]const u8{ "init", "--force", "--test-command", "zig test\nevil" }, false);
    try std.testing.expectEqual(@as(u8, 2), nl.exit_code);
    try std.testing.expect(!nl.write_config);

    // The embeddability predicate: ordinary commands (including backslashes, which
    // the escape-free reader treats literally) are accepted; quotes and control
    // bytes are rejected.
    try std.testing.expect(zentinel.testCommandEmbeddable("zig build test -Dfoo=bar"));
    try std.testing.expect(zentinel.testCommandEmbeddable("C:\\zig\\zig.exe test"));
    try std.testing.expect(!zentinel.testCommandEmbeddable("a\" b"));
    try std.testing.expect(!zentinel.testCommandEmbeddable("a\tb"));
}

test "config-aware init accepts --backend ast" {
    const out = dispatch(&[_][]const u8{ "init", "--backend", "ast" }, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expect(out.write_config);
}

test "init only writes the stable AST backend; --backend zir (or the retired air) is rejected" {
    const zir = dispatch(&[_][]const u8{ "init", "--backend", "zir" }, false);
    try std.testing.expectEqual(@as(u8, 2), zir.exit_code);
    try std.testing.expect(zir.error_code == .cli_invalid_option);
    try std.testing.expect(!zir.write_config);
    try std.testing.expectEqualStrings("zir", zir.detail);

    // `air` was retired and is now just an unknown backend value; init still
    // accepts only `ast`, so it is rejected with the value echoed as the detail.
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

// --- Read-side path containment (audit F-5) -----------------------
//
// The write side rejects an out-of-root `--output`; the read side must honor the
// same root-containment contract for the untrusted read paths so the CLI no
// longer claims a guarantee it does not enforce. `readPathOutsideRootOption`
// flags a `--input-report`/`--file` value that escapes the root (absolute or a
// `..` segment) -- the same `config.isOutsideRoot` test as the write side --
// while legitimate in-root reads pass.

test "readPathOutsideRootOption rejects out-of-root --input-report and --file (F-5)" {
    // Absolute and `..`-traversal read paths escape the project root and are named
    // for a clear usage error.
    try std.testing.expectEqualStrings("--input-report", zentinel.readPathOutsideRootOption(&[_][]const u8{ "m", "--input-report", "/abs/outside.json" }).?);
    try std.testing.expectEqualStrings("--input-report", zentinel.readPathOutsideRootOption(&[_][]const u8{ "m", "--input-report", "../../../tmp/outside.json" }).?);
    try std.testing.expectEqualStrings("--file", zentinel.readPathOutsideRootOption(&[_][]const u8{ "suggest", "--file", "/etc/passwd" }).?);

    // Legitimate in-root reads (the default report path, a relative doc path) pass.
    try std.testing.expect(zentinel.readPathOutsideRootOption(&[_][]const u8{ "m", "--input-report", "zig-out/zentinel/report.json" }) == null);
    try std.testing.expect(zentinel.readPathOutsideRootOption(&[_][]const u8{ "suggest", "--file", "docs/CLI_SPEC.md" }) == null);
    try std.testing.expect(zentinel.readPathOutsideRootOption(&[_][]const u8{"review-tests"}) == null);
}

test "explicit --config is resolved under --root, not the process cwd" {
    const resolved = try zentinel.resolveConfigPathForRoot(std.testing.allocator, .{
        .root = "proj",
        .config_path = "cwd-only.toml",
        .config_explicit = true,
    });
    defer std.testing.allocator.free(resolved);
    try std.testing.expectEqualStrings("proj/cwd-only.toml", resolved);
}

test "explicit --config symlink escapes are rejected as containment errors" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "proj");
    try tmp.dir.writeFile(io, .{ .sub_path = "outside.toml", .data = zentinel.default_config });
    try tmp.dir.symLink(io, "../outside.toml", "proj/link.toml", .{});
    var project_dir = try tmp.dir.openDir(io, "proj", .{ .iterate = true });
    defer project_dir.close(io);
    try std.testing.expect(zentinel.config.pathEscapesRoot(io, project_dir, "link.toml"));
}

test "doctest missing-file diagnostics redact secret-like path values" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const secret_path = "docs/ghp_abcdefghijklmnopqrstuvwxyz0123456789/missing.md";
    const redacted = try zentinel.redactCliDiagnosticPath(a, secret_path);
    try std.testing.expect(std.mem.indexOf(u8, redacted, secret_path) == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "[REDACTED]") != null or std.mem.indexOf(u8, redacted, "<path>") != null);
}

test "cleanup warning text is a stable CLI diagnostic" {
    const warning = try zentinel.cleanupWarningText(std.testing.allocator, 2);
    defer std.testing.allocator.free(warning);
    try std.testing.expectEqualStrings(
        "warning: failed to remove 2 mutation workspace(s)\n",
        warning,
    );
}

test "CLI cleanup warning emission writes only when cleanup failures occur" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    try zentinel.emitCleanupWarningIfNeeded(0, &out.writer);
    try std.testing.expectEqualStrings("", out.writer.buffer[0..out.writer.end]);
    try zentinel.emitCleanupWarningIfNeeded(2, &out.writer);
    try std.testing.expectEqualStrings(
        "warning: failed to remove 2 mutation workspace(s)\n",
        out.writer.buffer[0..out.writer.end],
    );
    // The emitter renders EXACTLY cleanupWarningText -- one source for the
    // diagnostic string, so the two functions cannot drift apart.
    const text = try zentinel.cleanupWarningText(std.testing.allocator, 2);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings(text, out.writer.buffer[0..out.writer.end]);
}

// --- Per-command --help (docs/CLI_SPEC.md "Per-command `--help`") -----------

test "per-command --help and -h route every option-taking command to its help topic" {
    const Case = struct { cmd: []const u8, topic: zentinel.HelpTopic };
    const cases = [_]Case{
        .{ .cmd = "run", .topic = .run },
        .{ .cmd = "init", .topic = .init },
        .{ .cmd = "check", .topic = .check },
        .{ .cmd = "list-mutants", .topic = .list_mutants },
        .{ .cmd = "doctest", .topic = .doctest },
        .{ .cmd = "explain", .topic = .explain },
        .{ .cmd = "suggest", .topic = .suggest },
        .{ .cmd = "review-tests", .topic = .review_tests },
        .{ .cmd = "version", .topic = .version },
    };
    for (cases) |case| {
        const long = zentinel.route(&[_][]const u8{ case.cmd, "--help" });
        try std.testing.expect(std.meta.activeTag(long) == .command_help);
        try std.testing.expectEqual(case.topic, long.command_help);
        const short = zentinel.route(&[_][]const u8{ case.cmd, "-h" });
        try std.testing.expect(std.meta.activeTag(short) == .command_help);
        try std.testing.expectEqual(case.topic, short.command_help);
    }
}

test "every command help block is a deterministic plain usage block" {
    for (std.enums.values(zentinel.HelpTopic)) |topic| {
        const h = zentinel.commandHelpText(topic);
        try std.testing.expect(std.mem.startsWith(u8, h, "zentinel "));
        try std.testing.expect(std.mem.indexOf(u8, h, "Usage:\n  zentinel") != null);
        try std.testing.expect(std.mem.indexOf(u8, h, "Options:") != null);
        // Plain text only: no ANSI escapes in snapshot-stable help (S-303).
        try std.testing.expect(std.mem.indexOfScalar(u8, h, 0x1b) == null);
        try std.testing.expect(std.mem.endsWith(u8, h, "\n"));
    }
}

test "run --help documents the parser's run options and not the rejected --backend" {
    const h = zentinel.commandHelpText(.run);
    for ([_][]const u8{
        "--operator <name>",
        "--mutant <id>",
        "--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>",
        "--jobs <n>",
        "--fail-on-survivors",
        "--report <text|json|jsonl|junit>",
        "--output <path>",
        "--no-cache",
        "--verbose",
        "--quiet",
    }) |flag| {
        try std.testing.expect(std.mem.indexOf(u8, h, flag) != null);
    }
    // run rejects --backend (list-mutants-only), so help must not advertise it.
    try std.testing.expect(std.mem.indexOf(u8, h, "--backend") == null);
}

test "init, list-mutants, doctest, and AI help blocks list their owned options" {
    const init_h = zentinel.commandHelpText(.init);
    for ([_][]const u8{ "--force", "--name <name>", "--test-command <command>", "--backend <ast>" }) |flag| {
        try std.testing.expect(std.mem.indexOf(u8, init_h, flag) != null);
    }
    const lm = zentinel.commandHelpText(.list_mutants);
    for ([_][]const u8{ "--operator <name>", "--format <text|json>", "--backend <ast|zir>" }) |flag| {
        try std.testing.expect(std.mem.indexOf(u8, lm, flag) != null);
    }
    const dt = zentinel.commandHelpText(.doctest);
    for ([_][]const u8{ "--file <path>", "--case <case-ref>", "--format <text|json>", "--mutate" }) |flag| {
        try std.testing.expect(std.mem.indexOf(u8, dt, flag) != null);
    }
    for ([_]zentinel.HelpTopic{ .explain, .suggest, .review_tests }) |topic| {
        const h = zentinel.commandHelpText(topic);
        for ([_][]const u8{ "--ai-provider <disabled|stub|local|remote>", "--input-report <path>", "--format <text|json>" }) |flag| {
            try std.testing.expect(std.mem.indexOf(u8, h, flag) != null);
        }
    }
}

test "a help request after other run options still wins over option parsing" {
    const r = zentinel.route(&[_][]const u8{ "run", "--report", "json", "--help" });
    try std.testing.expect(std.meta.activeTag(r) == .command_help);
    try std.testing.expectEqual(zentinel.HelpTopic.run, r.command_help);
    // Without a help token the same argv still routes to the run command.
    const no_help = zentinel.route(&[_][]const u8{ "run", "--report", "json" });
    try std.testing.expect(std.meta.activeTag(no_help) == .run);
}

test "an unknown command with --help keeps its deterministic unknown-command failure" {
    try std.testing.expect(std.meta.activeTag(zentinel.route(&[_][]const u8{ "frobnicate", "--help" })) == .passthrough);
    const out = dispatch(&[_][]const u8{ "frobnicate", "--help" }, false);
    try std.testing.expectEqual(@as(u8, 2), out.exit_code);
    try std.testing.expect(out.error_code == .cli_unknown_command);
}

test "top-level help points at per-command help" {
    try std.testing.expect(std.mem.indexOf(
        u8,
        zentinel.help_text,
        "Run 'zentinel <command> --help' for command-specific options.",
    ) != null);
}

// --- init project-name inference (docs/CLI_SPEC.md `init`) ------------------

test "init --name overrides the generated project name" {
    const out = dispatch(&[_][]const u8{ "init", "--name", "myproj" }, false);
    try std.testing.expectEqual(@as(u8, 0), out.exit_code);
    try std.testing.expect(out.write_config);
    try std.testing.expectEqualStrings("myproj", out.init_name.?);
}

test "init --name rejects values the escape-free TOML cannot embed" {
    // A `"` would close the TOML basic string and inject structure.
    const quote = dispatch(&[_][]const u8{ "init", "--name", "a\" b" }, false);
    try std.testing.expectEqual(@as(u8, 2), quote.exit_code);
    try std.testing.expect(quote.error_code == .cli_invalid_option);
    try std.testing.expect(!quote.write_config);
    // An empty name would write a useless `name = ""`.
    const empty = dispatch(&[_][]const u8{ "init", "--name", "" }, false);
    try std.testing.expectEqual(@as(u8, 2), empty.exit_code);
    try std.testing.expect(!empty.write_config);
    // A missing value is the usual ZNTL_CLI_INVALID_OPTION usage error.
    const missing = dispatch(&[_][]const u8{ "init", "--name" }, false);
    try std.testing.expectEqual(@as(u8, 2), missing.exit_code);
    try std.testing.expect(missing.error_code == .cli_invalid_option);
}

test "project name inference recognizes the three build.zig.zon name forms" {
    const enum_form = ".{\n    .name = .zentinel,\n    .version = \"0.0.0\",\n}\n";
    try std.testing.expectEqualStrings("zentinel", zentinel.projectNameFromZon(enum_form).?);
    const quoted_enum_form = ".{ .name = .@\"my-proj\", .version = \"0.0.0\" }";
    try std.testing.expectEqualStrings("my-proj", zentinel.projectNameFromZon(quoted_enum_form).?);
    const legacy_string_form = ".{ .name = \"legacy\", .version = \"0.0.0\" }";
    try std.testing.expectEqualStrings("legacy", zentinel.projectNameFromZon(legacy_string_form).?);
}

test "project name inference returns null for missing or different fields" {
    try std.testing.expect(zentinel.projectNameFromZon(".{ .version = \"0.0.0\" }") == null);
    // `.names` is a different field, not a prefix match.
    try std.testing.expect(zentinel.projectNameFromZon(".{ .names = .{} }") == null);
    try std.testing.expect(zentinel.projectNameFromZon("") == null);
    // An escaped string value cannot be sliced verbatim and is declined.
    try std.testing.expect(zentinel.projectNameFromZon(".{ .name = \"a\\\"b\" }") == null);
}

test "projectNameEmbeddable accepts ordinary names and rejects unembeddable bytes" {
    try std.testing.expect(zentinel.projectNameEmbeddable("my-proj"));
    try std.testing.expect(zentinel.projectNameEmbeddable("proj_01"));
    try std.testing.expect(!zentinel.projectNameEmbeddable(""));
    try std.testing.expect(!zentinel.projectNameEmbeddable("a\"b"));
    try std.testing.expect(!zentinel.projectNameEmbeddable("a\nb"));
}

test "initConfigText substitutes the inferred project name and nothing else" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const text = try zentinel.initConfigText(a, null, "myproj");
    try std.testing.expect(std.mem.indexOf(u8, text, "name = \"myproj\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "name = \"example\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "commands = [\"zig build test\"]") != null);

    // Null and the template's own default keep the config byte-identical.
    try std.testing.expectEqualStrings(zentinel.default_config, try zentinel.initConfigText(a, null, null));
    try std.testing.expectEqualStrings(zentinel.default_config, try zentinel.initConfigText(a, null, "example"));

    // Name and test-command substitutions compose.
    const both = try zentinel.initConfigText(a, "zig build test -Dfoo", "myproj");
    try std.testing.expect(std.mem.indexOf(u8, both, "name = \"myproj\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, both, "commands = [\"zig build test -Dfoo\"]") != null);
}
