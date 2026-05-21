# 056 ZIR Backend Experiment

Sequential guard: start this task only after task 055 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement an explicitly opt-in ZIR backend experiment with source-mapping diagnostics.

## Scope

- Add ZIR backend selection behind experimental opt-in.
- Generate prototype candidates where source mapping is exact.
- Emit clear diagnostics for unsupported Zig internals.
- Compare applicable candidates against AST fixtures.

## Files allowed to modify

- `src/zir_backend.zig`
- `src/backends/**`
- `src/mutant.zig`
- `src/config.zig`
- `src/cli.zig`
- `docs/ZIR_BACKEND.md`
- `docs/CLI_SPEC.md`
- `test/zir_backend_test.zig`
- `test/cli_backend_experiment_test.zig`
- `test/fixtures/zir_backend/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/air_backend.zig`
- `src/ai/**`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add a failing config test proving ZIR requires explicit opt-in.
- Add a failing CLI test proving `list-mutants --backend zir` is rejected before task `056` lands and accepted only by this task's explicit experimental opt-in.
- Add a failing ZIR source-mapping fixture test.
- Add a failing diagnostic artifact test proving unsupported ZIR evidence is written under `artifacts/pipeline/<task-id>/experimental-backend-diagnostics/`.
- Add a failing parity test for an AST-compatible operator where practical.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- AST remains the default backend.
- `list-mutants --backend zir` is implemented as an experimental opt-in and does not affect stable AST defaults.
- ZIR reports identify `backend` and `backend_stability` using report v1 fields only.
- Unsupported ZIR cases produce out-of-report diagnostics, not schema-invalid report fields or silent misreports.
- Unsupported ZIR cases write task-scoped diagnostics under `artifacts/pipeline/<task-id>/experimental-backend-diagnostics/`.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- AIR backend work.
- Stabilizing ZIR as default.
- AI source-mapping decisions.

## Suggested implementation approach

1. Gate all ZIR behavior behind config and CLI opt-in.
2. Use pinned Zig `0.16.0` public APIs where possible.
3. Skip candidates when source mapping is not exact.
4. Document version coupling in `docs/ZIR_BACKEND.md`.

## Dogfooding implications

ZIR experiments do not affect stable dogfood defaults.

## Follow-up tasks

- `tasks/057-air-backend-experiment.md`
