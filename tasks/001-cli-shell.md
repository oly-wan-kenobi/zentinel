# 001 CLI Shell

Sequential guard: start this task only after task 000 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement the Phase 0 CLI shell for `--help`, `version`, and `init` without mutation behavior.

## Scope

- Add deterministic command dispatch.
- Render help text matching `docs/CLI_SPEC.md`.
- Print zentinel version.
- Generate a default `zentinel.toml` with stable contents.
- Parse `--no-color` as the only global option owned by this task.
- Support `init --force` as the only command-specific option in this task.

## Files allowed to modify

- `src/main.zig`
- `src/cli.zig`
- `src/root.zig`
- `test/cli_test.zig`
- `test/snapshots/cli_help.txt`
- `test/snapshots/init_config.toml`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutation_engine.zig`
- `src/backends/**`
- `src/runner.zig`
- `src/ai/**`

## Required tests

- Add failing snapshot tests for help output before implementing rendering.
- Add a failing test for `version` output.
- Add a failing test for `init` refusing to overwrite an existing config.
- Add a failing test for `init --force` overwriting an existing config with the deterministic default template.
- Add a failing test that a known future command such as `run` returns `ZNTL_CLI_COMMAND_NOT_IMPLEMENTED`.
- Add a failing test that a truly unknown command returns `ZNTL_CLI_UNKNOWN_COMMAND`.
- Add a failing test that `--no-color` parses before command dispatch and keeps help output byte-stable.
- Add a failing test that config-aware init options owned by task 002, such as `--test-command`, return `ZNTL_CLI_INVALID_OPTION` until implemented.
- Run `zig build test` after implementation.

## Acceptance criteria

- `zentinel --help` is deterministic.
- `zentinel version` prints zentinel version and Zig policy label without requiring mutation components.
- `zentinel init` writes a valid default config.
- `zentinel init --force` overwrites only `zentinel.toml` and writes the same deterministic default config.
- Known future commands return a deterministic not-implemented usage failure.
- Unknown commands return an unknown-command usage failure.
- `--no-color` is accepted globally and does not change non-colored snapshot output.
- No AI or mutation command performs real work yet.

## Non-goals

- Full option parser beyond global `--no-color` and `init --force`.
- Config-aware init options such as `--test-command` and `--backend`.
- Config validation beyond writing default content.
- Running Zig tests.
- Listing mutants.

## Suggested implementation approach

1. Define a small command enum.
2. Keep stdout/stderr rendering injectable for tests.
3. Store snapshot text in test fixtures.
4. Keep init template in code or a testable constant until a config module exists.

## Dogfooding implications

CLI snapshots will later be mutation targets for report and command behavior. This task creates stable text surfaces for future dogfood review.

## Follow-up tasks

- `tasks/002-config-parser.md`
