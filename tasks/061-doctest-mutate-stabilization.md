# 061 Doctest Mutate Stabilization

Sequential guard: start this task only after task 059 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Stabilize `zentinel doctest --mutate` from fixture experiment into a documented, deterministic opt-in documentation mutation surface.

## Scope

- Promote experimental doctest mutation behavior only where deterministic evidence is proven.
- Define stable report fields for documentation mutants.
- Preserve normal doctest pass/fail as the gate before mutation-aware execution.
- Keep mutation-aware doctests opt-in.

## Files allowed to modify

- `src/doctest/**`
- `src/mutant_runner.zig`
- `src/report.zig`
- `docs/DOCTEST_MUTATION_STRATEGY.md`
- `schemas/doctest.report.v1.schema.json`
- `test/doctest_mutate_stabilization_test.zig`
- `test/fixtures/doctest/mutation_stabilization/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/zir_backend.zig`
- `src/air_backend.zig`
- `src/ai/**`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add a failing stabilization test proving `doctest --mutate` rejects non-opt-in documentation.
- Add a failing deterministic report snapshot for killed, survived, skipped, and invalid documentation mutants.
- Add a failing test that normal doctest failure prevents mutation-aware execution for that case.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Mutation-aware doctests are documented as opt-in and deterministic.
- Documentation mutant reports use stable IDs and canonical ordering.
- Normal doctest failure always blocks mutation-aware execution for the affected case.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- AI explanations for doctest survivors.
- ZIR or AIR doctest mutation.
- Making all public docs mutation-gated by default.

## Suggested implementation approach

1. Start from the fixture experiment behavior in task 039.
2. Add contract tests around opt-in, ordering, and report status before changing implementation.
3. Keep doctest mutation reporting aligned with canonical mutation report semantics.
4. Update docs only where behavior becomes stable.

## Dogfooding implications

Stable doctest mutation makes documentation examples stronger dogfood targets after normal executable docs are reliable.

## Follow-up tasks

- `tasks/062-property-generator-infrastructure.md`
