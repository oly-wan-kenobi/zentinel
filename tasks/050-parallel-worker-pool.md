# 050 Parallel Worker Pool

Sequential guard: start this task only after task 049 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement deterministic parallel mutant execution without changing report ordering.

## Scope

- Add a bounded worker pool.
- Run mutants concurrently when `--jobs <n>` or normalized `run.jobs` allows it.
- Preserve canonical report ordering independent of worker count.
- Add deterministic scheduling evidence.

## Files allowed to modify

- `src/worker_pool.zig`
- `src/mutant_runner.zig`
- `src/report.zig`
- `src/config.zig`
- `src/cli.zig`
- `src/run_command.zig`
- `test/worker_pool_test.zig`
- `test/run_command_test.zig`
- `test/fixtures/worker_pool/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `docs/**`

## Required tests

- Add a failing test proving worker count does not change report ordering or IDs.
- Add a failing run-command test proving `--jobs <n>` overrides normalized `run.jobs`, rejects non-positive values, and remains bounded.
- Add a failing config integration test proving normalized `run.jobs` greater than `1` enables the worker pool instead of being rejected after this task.
- Add a failing test proving concurrent workers use dedicated writable workspace, local `.zig-cache`, and `zig-out` paths and cannot clobber another worker's temporary build artifacts.
- Add a failing test for worker error propagation.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Serial and parallel runs produce equivalent reports except normalized durations.
- `--jobs <n>` and `run.jobs` are both implemented by this task and choose only worker count, not report ordering or mutation semantics.
- Parallel runs never share writable workspaces, local build caches, output directories, or scratch artifact paths between active workers.
- Worker failures are deterministic and visible.
- Default behavior remains conservative.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- AI commands.
- ZIR/AIR backend support.
- Performance benchmark baselines beyond smoke coverage.

## Suggested implementation approach

1. Separate execution ordering from report ordering.
2. Keep worker count explicit and bounded.
3. Use deterministic fixture workloads.
4. Avoid changing mutator semantics.

## Dogfooding implications

Parallel execution must not make dogfood reports nondeterministic.

## Follow-up tasks

- `tasks/051-fail-fast-impact-analysis.md`
