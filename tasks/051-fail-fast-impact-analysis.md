# 051 Fail Fast and Impact Analysis

Sequential guard: start this task only after task 050 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement fail-fast and deterministic test impact analysis for mutation runs.

## Scope

- Add fail-fast behavior for baseline and configured mutant classes.
- Refine same-file and package impact analysis.
- Accept and implement `test.selection = "impact_graph"`; task `051` is the first task allowed to accept `impact_graph`.
- Record skipped or shortened execution with deterministic reasons.

## Files allowed to modify

- `src/test_selection.zig`
- `src/run_command.zig`
- `src/runner.zig`
- `src/report.zig`
- `test/fail_fast_impact_test.zig`
- `test/fixtures/impact_analysis/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `src/mutators/**`

## Required tests

- Add a failing test for baseline fail-fast behavior.
- Add a failing test for deterministic impact-analysis ordering.
- Add a failing test that skipped mutants include documented reasons.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Fail-fast does not hide survivors from final reporting.
- Impact analysis selects tests deterministically.
- Report metadata explains skipped or shortened work.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Parallel worker implementation.
- AI test suggestions.
- ZIR/AIR backend support.

## Suggested implementation approach

1. Build on existing test selection.
2. Keep skip reasons enumerated.
3. Add snapshot coverage for report diagnostics.
4. Prefer conservative full-suite fallback when uncertain.

## Dogfooding implications

Impact analysis must keep future dogfood runs reviewable and conservative.

## Follow-up tasks

- `tasks/052-performance-benchmarks.md`
