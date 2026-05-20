# 062 Property Generator Infrastructure

Sequential guard: start this task only after task 061 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Add deterministic property-generator infrastructure for invariants that require generated coverage.

## Scope

- Implement minimal seeded generator support for structural property tests.
- Record seed, generated case count, invariant, and shrink status in property reports.
- Integrate property evidence with pipeline verification artifacts.
- Keep generators deterministic and local.

## Files allowed to modify

- `src/property/**`
- `test/support/property.zig`
- `test/property_generator_test.zig`
- `test/fixtures/pipeline/property_tests/**`
- `docs/PROPERTY_TEST_POLICY.md`
- `docs/VERIFICATION_PIPELINE.md`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add a failing property-generator test proving the same seed emits the same case sequence.
- Add a failing test proving failed property reports include seed, invariant, generated count, and shrink status.
- Add a failing fixture for missing property evidence on a high-risk task.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Property generators are deterministic for a recorded seed.
- Property reports contain enough evidence for reruns.
- Pipeline verification can distinguish missing property evidence from passing property evidence.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Choosing a third-party property testing dependency.
- Generating arbitrary Zig programs.
- Replacing focused unit or fixture tests.

## Suggested implementation approach

1. Build a tiny deterministic generator interface first.
2. Use fixed seeds in tests and print failing seeds.
3. Keep shrinking optional but report whether it ran.
4. Avoid broad test harness refactors.

## Dogfooding implications

Property generators make deterministic surfaces such as ordering, IDs, and cache keys harder to regress during dogfood.

## Follow-up tasks

- `tasks/063-pipeline-metadata-validator.md`
