# 020 Test Selection Same File

Sequential guard: start this task only after tasks 018 and 019 are complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement the default `same_file_then_package` test selection strategy.

## Scope

- Discover same-file Zig tests for a mutated file.
- Select `zig test <file>` when appropriate.
- Fall back to configured test commands when same-file selection is unavailable.
- Record selection reason in reports.

## Files allowed to modify

- `src/test_selection.zig`
- `src/config.zig`
- `src/ast_backend.zig`
- `src/run_command.zig`
- `src/report.zig`
- `test/config_test.zig`
- `test/test_selection_test.zig`
- `test/fixtures/test_selection/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/sandbox.zig`
- `src/ai/**`
- `src/cache.zig`

## Required tests

- Add a failing test for same-file test selection.
- Add a failing test proving each generated selected command must pass an unmutated preflight before mutant classification when it was not part of the baseline command set.
- Add a failing test for fallback to configured commands.
- Add a failing test for deterministic selected test ordering.
- Reject `impact_graph` before task `051` with a failing config-validation test instead of downgrading it to `same_file_then_package`.
- Add a failing report snapshot showing selection metadata with required `strategy`, `selected`, `commands`, `preflight_commands`, and `fallback_used` fields and no unknown fields.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Default selection matches `docs/TEST_SELECTION.md`.
- Reports include strategy, selected tests, commands, generated-command `preflight_commands`, and fallback flag.
- Selection never uses AI.
- Full command fallback is deterministic.
- A generated selected command must pass an unmutated preflight before it can classify a mutant.

## Non-goals

- Impact graph.
- Parallel scheduling.
- Historical selection.

## Suggested implementation approach

1. Parse test declaration names and line numbers from source mapping.
2. Keep selected tests sorted by file, line, and name.
3. Build commands from normalized project-relative paths.
4. Integrate selection into `run` only after unit tests pass.

## Dogfooding implications

Same-file selection makes future self-mutation faster while preserving a clear fallback path.

## Follow-up tasks

- `tasks/021-cache-key-design.md`
