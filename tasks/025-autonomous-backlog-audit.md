# 025 Autonomous Backlog Audit

Sequential guard: start this task only after task 024 is complete in `tasks/STATUS.md`. No later-order implementation task may begin until this task has audited the remaining roadmap tasks and validation passes.

## Goal

Audit and refine the complete end-to-end implementation backlog now present in the task system.

## Scope

- Verify that sequential task files still exist for every remaining item needed to satisfy `docs/PROJECT_ACCEPTANCE_CRITERIA.md`.
- Maintain coverage for remaining Phase 2 stable mutators, Phase 3 performance, Phase 4 AI assistance, Phase 5 ZIR/AIR experiments, Phase 6 safety mode intelligence, Phase 7 dogfooding expansion, CI, release readiness, and final acceptance verification.
- Update `tasks/QUEUE.md` and `tasks/queue.json` only when the audit finds a concrete missing or stale task.
- Keep tasks small enough for one autonomous agent session each.
- Preserve machine-checkable task state and validator compatibility.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/026-*.md`
- `tasks/027-*.md`
- `tasks/028-*.md`
- `tasks/029-*.md`
- `tasks/030-*.md`
- `tasks/031-*.md`
- `tasks/032-*.md`
- `tasks/033-*.md`
- `tasks/034-*.md`
- `tasks/035-*.md`
- `tasks/036-*.md`
- `tasks/037-*.md`
- `tasks/038-*.md`
- `tasks/039-*.md`
- `tasks/040-*.md`
- `tasks/041-*.md`
- `tasks/042-*.md`
- `tasks/043-*.md`
- `tasks/044-*.md`
- `tasks/045-*.md`
- `tasks/046-*.md`
- `tasks/047-*.md`
- `tasks/048-*.md`
- `tasks/049-*.md`
- `tasks/050-*.md`
- `tasks/051-*.md`
- `tasks/052-*.md`
- `tasks/053-*.md`
- `tasks/054-*.md`
- `tasks/055-*.md`
- `tasks/056-*.md`
- `tasks/057-*.md`
- `tasks/058-*.md`
- `tasks/059-*.md`
- `tasks/060-*.md`
- `tasks/061-*.md`
- `tasks/062-*.md`
- `tasks/063-*.md`
- `tasks/064-*.md`
- `tasks/065-*.md`
- `tasks/066-*.md`
- `tasks/067-*.md`

## Files forbidden to modify

- `src/**`
- `test/**`
- `schemas/**`
- `scripts/**`
- `docs/**`

## Required tests

- Add a failing task-system fixture only if this audit adds or changes validator behavior through an inserted prerequisite task; do not deliberately corrupt the live queue merely to manufacture a failure.
- Audit the existing future task set, including inserted prerequisite tasks `061` through `067`, against `docs/ROADMAP.md` and `docs/PROJECT_ACCEPTANCE_CRITERIA.md`.
- Run `python3 scripts/validate_task_system.py` and require it to pass.
- Run JSON syntax validation for `tasks/queue.json` and `tasks/status.json`.

## Acceptance criteria

- The queue does not dead-end after the initial Phase 2 tasks.
- Every remaining minimum-product roadmap phase has concrete sequential tasks.
- Every backlog task file contains the standard required sections.
- Every backlog task file has a sequential guard.
- Every behavior-changing backlog task requires TDD-first implementation.
- `tasks/queue.json` includes every backlog task with dependencies, allowed files, forbidden files, phase, and state.
- Preview mutator work is not treated as required minimum-product implementation unless a later task explicitly names the preview operator.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing zentinel behavior.
- Changing architecture contracts.
- Adding new product features beyond documented roadmap and acceptance criteria.
- Reordering already completed tasks.

## Suggested implementation approach

1. Compare the queued backlog against `docs/ROADMAP.md` and `docs/PROJECT_ACCEPTANCE_CRITERIA.md`.
2. Add or adjust only the narrowest missing task when a coverage gap is found.
3. Preserve performance and AI tasks after stable deterministic execution tasks.
4. Keep experimental ZIR/AIR tasks explicitly opt-in and after stable AST behavior.
5. Preserve the final release-readiness and project acceptance verification task.

## Dogfooding implications

This task ensures dogfooding expansion is not left as prose. Future dogfood tasks must be concrete, executable, and validated by the task system.

## Follow-up tasks

- `tasks/026-errdefer-mutator.md`
