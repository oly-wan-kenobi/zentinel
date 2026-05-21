# 104 Output Bound Wording Cleanup

Sequential guard: start this task only after task `103` is complete and `tasks/status.json` names `104` as the active task. No later-order task may begin until this task is complete.

## Goal

Remove stale character-unit wording so future AI-context implementation tasks consistently use the canonical 4096 UTF-8 byte output excerpt bound.

## Scope

- Add validator coverage for the stale output-bound wording found after task `103`.
- Normalize the `zentinel.ai.context.v1` schema gap row to 4096 UTF-8 bytes.
- Normalize historical task/status wording that still describes the canonical output excerpt bound in characters.
- Update task `000` dependency wording so project bootstrap starts only after this cleanup.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/096-audit-finding-contract-closure.md`
- `tasks/104-output-bound-wording-cleanup.md`
- `tests/coverage-gaps/schemas.v1.json`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing structural validator guardrail rejecting stale character-unit wording in the AI-context output-bound cleanup targets.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before wording fixes.
- Run `python3 scripts/validate_task_system.py` while task `104` is active after fixes.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run `jq empty tasks/status.json tasks/queue.json tests/coverage-gaps/schemas.v1.json`.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` after marking task `104` complete.

## Acceptance criteria

- `tests/coverage-gaps/schemas.v1.json` describes the `zentinel.ai.context.v1` output excerpt bound as 4096 UTF-8 bytes.
- Historical task/status references updated by this task no longer describe the canonical output excerpt bound in characters.
- Task `000` depends on task `104` and names task `104` in its sequential guard.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Changing schema shape.
- Changing runtime product behavior.
- Editing canonical docs that already state 4096 UTF-8 bytes.
- Implementing AI provider or context behavior.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on the stale wording.
2. Replace only the stale wording with 4096 UTF-8 bytes wording.
3. Keep historical completion evidence accurate while removing the misleading unit.
4. Re-run validator, Python compilation, JSON syntax checks, and whitespace checks.

## Dogfooding implications

No zentinel runtime exists yet. This task prevents future AI-context implementation and dogfood tasks from copying the wrong output-bound unit.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
