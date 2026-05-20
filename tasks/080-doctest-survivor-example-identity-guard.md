# 080 Doctest Survivor Example Identity Guard

Sequential guard: start this task only after task 079 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Ensure doctest survivor AI examples preserve the documented split between ordinary `dt_...` doctest case IDs, mutation-aware `dm_...` report entry IDs, and survivor-only `ds_...` refs.

## Scope

- Add a structural validator guardrail for the `doctest_survivor` JSON example in `docs/DOCTEST_AI_INTEGRATION.md`.
- Align the survivor example so `source_case.id` remains `dt_...` and `mutation_case.id` uses `dm_...`.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/080-doctest-survivor-example-identity-guard.md`
- `tasks/000-project-bootstrap.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `docs/MUTATOR_SPEC.md`
- `.claude/**`

## Required tests

- Add a failing validator guardrail proving the `doctest_survivor` JSON example rejects a `mutation_case.id` that reuses the ordinary `dt_...` case ID.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating the doctest AI example.
- Run `python3 scripts/validate_task_system.py` after the example is aligned.

## Acceptance criteria

- The `doctest_survivor` minimal evidence example uses `dt_...` for `source_case.id`.
- The same example uses `dm_...` for `mutation_case.id`.
- The validator preserves the example identity split.
- No product implementation files are changed.

## Non-goals

- Implementing `zentinel doctest explain-survivor`.
- Changing the doctest report schema.
- Changing survivor-ref derivation.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on the current `dt_...` mutation-case example.
2. Update only the `doctest_survivor` example ID needed to match the existing mutation-aware report contract.
3. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task prevents future doctest mutation dogfood and survivor AI work from copying an invalid case-ID join model.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
