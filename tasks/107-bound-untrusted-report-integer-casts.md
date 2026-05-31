# 107 Bound Untrusted Report Integer Casts

Sequential guard: start this task only after task `106` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (High, memory-safety). A crafted `--input-report` integer panics the process via unchecked `@intCast` to u32 (src/ai/command.zig:209, :337; src/ai/doctest_command.zig:123) — abort in Debug/ReleaseSafe, silent truncation in ReleaseFast.

## Goal

Make advisory AI commands reject out-of-range integers in an untrusted `--input-report` with a clean `ZNTL_AI_*` error instead of aborting or silently truncating. All narrowing of report-sourced integers must be bounds-checked.

## Scope

- Clamp/validate every report-sourced integer before narrowing to u32 (span line/column fields, display_id, doctest line/column).
- Treat out-of-range or non-integer values as a structured invalid-report error, never a panic.

## Files allowed to modify

- `src/ai/command.zig`
- `src/ai/doctest_command.zig`
- `src/ai/context.zig`
- `test/ai_command_test.zig`
- `test/fixtures/ai/**`
- `artifacts/pipeline/107/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/report.zig`
- `src/run_command.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test that feeds `explain` an `--input-report` with `span.line_start` and `display_id` set to 2^32+1 and asserts a clean non-panicking exit with a `ZNTL_AI_*` diagnostic (not exit 134).
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Out-of-range or non-integer report integers produce a documented `ZNTL_AI_*` error and a non-abnormal exit.
- No `@intCast`/`@truncate` on report-sourced integers can panic or silently wrap (verified for Debug, ReleaseSafe, ReleaseFast).

## Non-goals

- Re-architecting the AI command engines.
- Adding a full JSON schema validator for reports.

## Suggested implementation approach

1. Add a `clampU32`/checked-narrowing helper and route every report-sourced narrowing through it.
2. Map out-of-range to the existing invalid-report failure path.

## Dogfooding implications

zentinel can ingest its own and third-party reports without crashing on malformed integers.

## Follow-up tasks

- None predefined.
