# 087 Dogfood Release Gate Sequencing

Sequential guard: start this task only after task `086` is complete and `tasks/status.json` names `087` as the next queued task. No later-order task may begin until this task is complete.

## Goal

Split initial dogfood CI from the final release dogfood gate so autonomous agents do not mistake task `059` for complete release dogfood evidence.

## Scope

- Rename task `059` from production dogfood CI to initial advisory dogfood CI.
- Add task `085` as the final release dogfood gate before task `060`.
- Update task dependencies and queue/status metadata so task `060` depends on task `085`.
- Add validator guardrails for the dogfood release-gate sequence.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/087-dogfood-release-gate-sequencing.md`
- `tasks/000-project-bootstrap.md`
- `tasks/058-safety-mode-matrix.md`
- `tasks/059-initial-dogfood-ci.md`
- `tasks/085-final-dogfood-release-gate.md`
- `tasks/060-release-acceptance-verification.md`
- `tests/coverage-gaps/failure_modes.v1.json`
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

- Add a failing validator guardrail that rejects task `059` if it still uses production dogfood wording.
- Add a failing validator guardrail requiring task `085` to exist, execute before task `060`, and depend on task `067`.
- Add a failing validator guardrail requiring task `060` to depend on task `085`.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating task metadata.
- Run `python3 scripts/validate_task_system.py` after the contracts are aligned.

## Acceptance criteria

- Task `059` is named and scoped as initial advisory dogfood CI.
- Task `085` is queued as the final release dogfood gate after late hardening tasks and before release acceptance.
- Task `060` depends on task `085`.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing dogfood runtime behavior.
- Changing release acceptance beyond requiring final dogfood evidence.
- Moving tasks `061`, `062`, `064`, `065`, `066`, or `067`.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on current task sequencing.
2. Rename task `059`, add task `085`, and update dependencies.
3. Complete this pre-bootstrap sequencing task and leave project bootstrap as the next dependency-ready task.

## Dogfooding implications

No runtime dogfood exists yet. This task prevents initial advisory dogfood CI from being confused with the final release dogfood gate.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
