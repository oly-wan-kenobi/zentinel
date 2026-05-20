# 016 Minimal Run Command

Sequential guard: start this task only after task 015 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement `zentinel run` for a single-threaded Phase 1 flow over configured files and stable AST mutators.

## Scope

- Load config.
- Validate Zig version.
- Run baseline tests.
- Generate Phase 1 AST candidates.
- Execute mutants serially.
- Write JSON report and text summary.

## Files allowed to modify

- `src/cli.zig`
- `src/main.zig`
- `src/run_command.zig`
- `src/report.zig`
- `src/ast_backend.zig`
- `test/run_command_test.zig`
- `test/fixtures/run_command/**`
- `test/snapshots/run_command_*.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/worker_pool.zig`
- `src/cache.zig`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `src/mutators/optional.zig`

## Required tests

- Add a failing end-to-end fixture test for one killed mutant.
- Add a failing end-to-end fixture test for one survived mutant.
- Add a failing test for baseline failure exit behavior.
- Add a failing JSON report snapshot proving baseline failure sets `run.status = baseline_failed`, records baseline command evidence, emits no mutant result with `baseline_failed`, and leaves summary counts at zero.
- Add a failing JSON report snapshot proving a completed run sets `run.status = completed`, includes deterministic mutant entries, and derives summary counts from those entries.
- Run `zig build test`.

## Acceptance criteria

- `zentinel run` works for small fixture projects.
- Reports include deterministic mutant entries and summary counts.
- Baseline failure stops mutant execution and is represented as a run-level status with structured baseline command evidence.
- Output remains concise and survivor-focused.

## Non-goals

- Parallel execution.
- Cache.
- AI advisory output.
- Experimental backends.

## Suggested implementation approach

1. Wire existing modules with minimal orchestration.
2. Keep execution serial and easy to debug.
3. Use fixtures rather than broad repository scans.
4. Avoid adding configuration options not already documented.

## Dogfooding implications

This is the first task after which fixture-only dogfooding can run in a meaningful way.

## Follow-up tasks

- `tasks/017-list-mutants-command.md`
