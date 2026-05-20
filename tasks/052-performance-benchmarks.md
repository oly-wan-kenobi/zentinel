# 052 Performance Benchmarks

Sequential guard: start this task only after task 051 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Add machine-readable performance benchmarks and cache/parallel equivalence checks.

## Scope

- Add benchmark fixtures or scripts for mutation and doctest workloads.
- Record normalized benchmark output.
- Check cached/uncached and serial/parallel equivalence.
- Wire report cache diagnostics through the reserved `diagnostics.cache` report v1 field when cache behavior is observable.
- Document concrete initial CI smoke budgets for fixture dogfood, selected production dogfood, doctests, and benchmark smoke runs.

## Files allowed to modify

- `src/cache.zig`
- `src/worker_pool.zig`
- `src/report.zig`
- `schemas/report.v1.schema.json`
- `scripts/**`
- `test/performance_benchmark_test.zig`
- `test/fixtures/performance/**`
- `docs/PERFORMANCE_STRATEGY.md`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add a failing benchmark-output schema or snapshot test before implementation.
- Add a failing equivalence test for cached versus uncached reports that ignores only durations and `diagnostics.cache`.
- Add a failing report schema or snapshot test for cache diagnostics under `diagnostics.cache`.
- Add a failing documentation check or snapshot proving numeric CI smoke budgets are present in `docs/PERFORMANCE_STRATEGY.md`.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Benchmark output is machine-readable.
- Cached and uncached reports differ only in `diagnostics.cache` and durations.
- Serial and parallel reports differ only in durations.
- `docs/PERFORMANCE_STRATEGY.md` contains concrete initial CI smoke budgets for later dogfood and doctest tasks.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Release gating.
- AI commands.
- Experimental backend performance tuning.

## Suggested implementation approach

1. Keep benchmark fixtures small.
2. Normalize volatile fields.
3. Record budget in `docs/PERFORMANCE_STRATEGY.md`.
4. Fail closed on nondeterministic output.

## Dogfooding implications

Performance evidence sets budgets for later production dogfood and CI.

## Follow-up tasks

- `tasks/053-ai-provider-and-context.md`
