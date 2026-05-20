# 003 Test Harness

Sequential guard: start this task only after task 002 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Create deterministic test helpers for snapshots, temp directories, command-output capture, and fixture paths.

## Scope

- Add reusable testing utilities.
- Normalize absolute paths and durations in snapshots.
- Support CLI tests without relying on global process state.
- Extend the bootstrap top-level discovery so future nested `test/**/*_test.zig` files are discovered automatically.
- Keep helpers small and documented through tests.

## Files allowed to modify

- `test/support/**`
- `test/harness_test.zig`
- `test/*_test.zig`
- `test/fixtures/harness/test_discovery/**`
- `build.zig`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ast_backend.zig`
- `src/runner.zig`
- `src/ai/**`

## Required tests

- Add failing tests for path normalization, duration normalization, and snapshot comparison.
- Add a failing test that proves temp fixture directories are isolated.
- Add a failing build integration test or fixture under `test/fixtures/harness/test_discovery/**` proving a nested future test file would be included by `zig build test` without editing `build.zig`.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Snapshot tests are deterministic across machines.
- Test helpers do not require network access.
- Temporary directories are cleaned or clearly scoped to test output.
- Existing CLI/config tests still pass.
- Future nested `test/**/*_test.zig` files are picked up by `zig build test` without per-task `build.zig` edits.

## Non-goals

- Real process runner.
- Mutation sandbox.
- Benchmark harness.

## Suggested implementation approach

1. Build pure normalization helpers first.
2. Add snapshot assertion helpers second.
3. Extend the bootstrap top-level discovery to recursive test discovery in `build.zig` for files ending in `_test.zig` under `test/`.
4. Exclude fixture source files that are not test entrypoints.
5. Keep helper API narrow so future agents can reason about it.

## Dogfooding implications

The harness makes future dogfood reports stable by normalizing volatile output.
It also extends the bootstrap top-level discovery to nested test files once reusable test helpers exist.

## Follow-up tasks

- `tasks/004-fixture-system.md`
