# 033 Doctest Runner

Sequential guard: start this task only after task 032 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement normal doctest execution for Zig, CLI, and config cases without mutation support.

## Scope

- Generate isolated temporary workspaces for doctest cases.
- Execute `zig`, `zig test`, `zig compile_fail`, `bash cli`, `toml config`, and `toml config_fail` cases.
- Classify deterministic doctest statuses.
- Capture bounded command evidence.

## Files allowed to modify

- `src/doctest/runner.zig`
- `src/doctest/workspace.zig`
- `src/doctest/case.zig`
- `src/runner.zig`
- `src/config.zig`
- `src/cli.zig`
- `test/doctest_runner_test.zig`
- `test/fixtures/doctest/runner/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/doctest/snapshot.zig`
- `src/mutators/**`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add failing tests for Zig compile-pass, Zig test pass, Zig compile-fail pass, CLI command pass, config pass, and config-fail pass.
- Add failing tests for timeout and unsupported CLI command rejection with `ZNTL_DOCTEST_COMMAND_REJECTED`.
- Add failing tests proving ordinary doctest failure statuses exit `1` and `expected_compile_error` remains a successful compile-fail status.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Required property tests

- Workspace generation path is stable for the same case hash.
- Original repository files remain unchanged after execution.
- Repeated execution of the same case produces equivalent normalized status.
- CLI command parsing rejects shell metacharacter variants consistently.

## Acceptance criteria

- Normal doctest cases can execute in isolation.
- Pass/fail status is determined only by deterministic execution.
- Compile-fail cases pass only on expected compiler failure.
- CLI examples execute only zentinel commands.
- No snapshot comparison beyond direct status exists yet.

## Non-goals

- `zentinel doctest` CLI command.
- Snapshot matching.
- Cache integration.
- `doctest --mutate`.

## TDD instructions

Start with a failing runner test using one extracted case. Implement the smallest workspace and runner path needed, then add additional case-type tests one at a time.

## Suggested implementation approach

1. Reuse the existing runner abstraction.
2. Generate workspaces under `.zig-cache/zentinel/doctest`.
3. Normalize paths in command evidence.
4. Keep the API serial and deterministic.

## Dogfooding implications

This task makes docs executable in principle, but dogfood should wait for snapshot matching and CLI integration.

## Follow-up tasks

- `tasks/034-doctest-snapshots.md`
