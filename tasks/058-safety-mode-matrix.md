# 058 Safety Mode Matrix

Sequential guard: start this task only after task 057 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement safety and optimization mode matrix execution and reporting.

## Scope

- Run configured modes per mutant.
- Support `--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>` as a single-invocation override of configured `zig.modes`.
- Distinguish safety-mode effects from test failures.
- Add deterministic mode-matrix report fields.
- Support mode-aware doctest examples where available.

## Files allowed to modify

- `src/safety_modes.zig`
- `src/runner.zig`
- `src/report.zig`
- `src/config.zig`
- `src/cli.zig`
- `src/run_command.zig`
- `docs/REPORT_FORMAT.md`
- `docs/ZIG_SEMANTICS.md`
- `schemas/report.v1.schema.json`
- `test/safety_mode_matrix_test.zig`
- `test/run_command_test.zig`
- `test/fixtures/safety_modes/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add a failing config test for mode selection.
- Add a failing run-command test for `--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>` override parsing and validation.
- Add a failing report test for mode-specific outcomes.
- Add a failing schema/doc test proving mode-matrix report fields are documented in `docs/REPORT_FORMAT.md` and represented in `schemas/report.v1.schema.json`.
- Add a failing schema/doc test proving optional `result.mode_matrix` fields preserve `result.mode` semantics as an additive `zentinel.report.v1` extension.
- Add a failing fixture for Debug versus ReleaseFast behavior.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Mode matrix output is deterministic.
- more than one configured `zig.modes` entry is accepted only after this task.
- `--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>` is implemented as an explicit override and invalid modes are rejected deterministically.
- Reports distinguish mode effects from normal test failures.
- Mode-matrix reporting uses optional `result.mode_matrix` and must preserve `result.mode` semantics unless a new report schema version is introduced.
- CI can limit modes by config.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Stabilizing ZIR/AIR.
- Changing default mode from Debug.
- AI mode classification.

## Suggested implementation approach

1. Model modes explicitly in runner inputs.
2. Sort mode results by documented mode order.
3. Normalize mode-specific diagnostics in snapshots.
4. Keep single-mode behavior unchanged.

## Dogfooding implications

Mode-aware fixtures prepare release dogfood for safety-sensitive code.

## Follow-up tasks

- `tasks/059-initial-dogfood-ci.md`
