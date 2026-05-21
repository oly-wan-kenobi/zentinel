# 005 Version Policy and Check Command

Sequential guard: start this task only after task 004 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement pinned Zig `0.16.0` version detection and the `zentinel check` command.

## Scope

- Add version discovery abstraction.
- Compare discovered Zig version against zentinel's pinned supported Zig version `0.16.0`.
- Surface deterministic diagnostics.
- Add `zentinel check` for config, Zig version, path, test command, and report output validation.
- Add the shared test-command parser in `src/command.zig` and validate configured test command strings without executing them.
- Add the shared global option parser for `--config <path>` and `--root <path>`.
- Ensure `check` performs no mutation discovery, patching, or test execution.

## Files allowed to modify

- `src/zig_version.zig`
- `src/command.zig`
- `src/check_command.zig`
- `src/config.zig`
- `src/cli.zig`
- `src/main.zig`
- `docs/ZIG_VERSION_POLICY.md`
- `test/zig_version_test.zig`
- `test/check_command_test.zig`
- `test/fixtures/check/**`
- `test/snapshots/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ast_backend.zig`
- `src/runner.zig`
- `src/ai/**`

## Required tests

- Add failing tests for supported version `0.16.0`, unsupported older/newer stable version, malformed version, and missing Zig executable diagnostic.
- Add failing CLI tests for `zentinel version` with supported Zig `0.16.0`, missing Zig executable, and unsupported Zig version.
- Add failing CLI tests that `zentinel check` treats missing Zig and unsupported Zig as fatal environment errors.
- Add a failing snapshot for unsupported-version wording.
- Add failing pure parser tests for quoted argv fields, unmatched quotes, empty argv, unsupported escapes, rejected metacharacters, rejected environment assignment, rejected variable expansion, and rejected command chaining before wiring `zentinel check`.
- Add failing CLI tests for `zentinel check` success, invalid config, missing config path with `ZNTL_CONFIG_NOT_FOUND`, unsupported Zig version, invalid include/exclude paths, invalid test command syntax with `ZNTL_CONFIG_INVALID_COMMAND`, and invalid report output directory.
- Add failing CLI tests that `--config <path>` and `--root <path>` parse before command dispatch for `zentinel check`, and that unowned global options still fail with `ZNTL_CLI_INVALID_OPTION`.
- Add a failing test that `zentinel check` does not execute configured test commands.
- Record durable verification evidence for the pinned supported Zig version: pinned supported Zig version `0.16.0`, local `zig version`, and match or mismatch result.
- No live latest-stable lookup is required.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Version policy matches `docs/ZIG_VERSION_POLICY.md`.
- Version checking is testable without invoking the real Zig binary.
- `zentinel version` reports Zig discovery status without making missing or unsupported Zig fatal for that command.
- `zentinel check` validates config, Zig version policy, paths, configured test commands, and report output directory.
- `--config <path>` and `--root <path>` follow the ownership matrix in `docs/CLI_SPEC.md`.
- Configured command strings are parsed by `src/command.zig`; task 014 must reuse the same parser for execution.
- Invalid configured command syntax reports `ZNTL_CONFIG_INVALID_COMMAND`; unsupported TOML and non-command value errors still use the config parse/value codes from `docs/ERROR_CODES.md`.
- `zentinel check` exits `0` for valid inputs and exits `2` for usage, config, environment, path, command-syntax, or output-directory failures.
- `zentinel check` exits `2` for missing or unsupported Zig.
- `zentinel check` does not generate mutants, patch source, or execute test commands.
- Unsupported versions fail before mutation work begins.
- Diagnostics include detected version and required policy.
- The compiled-in supported Zig version is stored in one version-policy module and set to `0.16.0`.
- Task status or release metadata records durable verification evidence for the pinned supported Zig version, local `zig version`, and match or mismatch result.
- The local `zig version` result verifies the environment against the documented pin; it does not choose the supported version.
- Unsupported versions fail with diagnostics that name the detected version and required `0.16.0` policy.

## Non-goals

- Downloading Zig.
- Supporting multiple Zig versions.
- Nightly support.

## Suggested implementation approach

1. Define a small interface for command execution or version provider.
2. Keep parsing pure and separately tested.
3. Store the supported version in one module.
4. Avoid invoking Zig in default unit tests.
5. Keep `src/check_command.zig` responsible for check orchestration so CLI dispatch stays thin.
6. Keep `src/command.zig` independent of `src/runner.zig`; the runner consumes parsed argv later and must not fork parser behavior.

## Dogfooding implications

Version validation is a future dogfood target because incorrect branches would weaken all runs.

## Follow-up tasks

- `tasks/006-report-schema.md`
