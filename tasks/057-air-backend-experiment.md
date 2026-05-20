# 057 AIR Backend Experiment

Sequential guard: start this task only after task 056 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement an explicitly opt-in AIR backend experiment with semantic diagnostics.

## Scope

- Add AIR backend selection behind experimental opt-in.
- Generate prototype candidates only when source mapping is exact.
- Record safety-mode metadata when available.
- Compare applicable candidates against AST fixtures.

## Files allowed to modify

- `src/air_backend.zig`
- `src/backends/**`
- `src/mutant.zig`
- `src/config.zig`
- `docs/AIR_BACKEND.md`
- `test/air_backend_test.zig`
- `test/fixtures/air_backend/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/zir_backend.zig`
- `src/ai/**`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add a failing config test proving AIR requires explicit opt-in.
- Add a failing AIR diagnostic test for unsupported mapping.
- Add a failing parity fixture where practical.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- AST remains the default backend.
- AIR reports identify backend and experimental stability.
- AIR failures degrade to clear diagnostics.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- ZIR backend work.
- Stabilizing AIR as default.
- Remote AI analysis.

## Suggested implementation approach

1. Keep AIR code isolated from stable AST paths.
2. Prefer explicit unsupported diagnostics over guessed mapping.
3. Snapshot backend metadata.
4. Document version coupling in `docs/AIR_BACKEND.md`.

## Dogfooding implications

AIR experiments remain outside protected stable dogfood scopes.

## Follow-up tasks

- `tasks/058-safety-mode-matrix.md`
