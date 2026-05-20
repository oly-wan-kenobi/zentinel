# 060 Release Acceptance Verification

Sequential guard: start this task only after task 085 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Verify final project acceptance criteria and release readiness contracts.

## Scope

- Check commands, schemas, docs, reports, final dogfood gate evidence, CI, and backend stability against project acceptance criteria.
- Add release acceptance fixtures or scripts.
- If release blockers are found, insert the smallest prerequisite task or tasks before this release gate using the Task Queue Manager task-control exception, mark this task blocked, and resume only after those prerequisites complete.
- Do not implement product behavior in this task.

## Files allowed to modify

- `docs/PROJECT_ACCEPTANCE_CRITERIA.md`
- `docs/ROADMAP.md`
- `docs/SCHEMA_REGISTRY.md`
- `scripts/**`
- `test/release_acceptance_test.zig`
- `test/fixtures/release/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing release acceptance check before completing the checklist.
- Run `python3 scripts/validate_task_system.py`.
- Run `zig build test`.
- Run all available dogfood, doctest, schema, and CI-equivalent checks, including final release dogfood evidence from task `085`.

## Acceptance criteria

- Every item in `docs/PROJECT_ACCEPTANCE_CRITERIA.md` is satisfied. If not, this task is blocked with concrete prerequisite task metadata.
- Final dogfood gate evidence from task `085` exists and satisfies the dogfood acceptance criteria.
- Schemas validate generated reports.
- Docs match public CLI/config/report behavior.
- AST remains stable default and experimental backends remain opt-in.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Adding new product features.
- Changing release criteria to fit implementation gaps.
- Implementing missing behavior directly.

## Suggested implementation approach

1. Build a release checklist script or fixture.
2. Fail on missing evidence.
3. Use project-relative artifact paths.
4. Record blockers as prerequisite task metadata, not prose-only notes.

## Dogfooding implications

Final acceptance includes archived dogfood and doctest evidence for release review.

## Follow-up tasks

- None predefined. If release blockers are found, add prerequisite tasks before this gate and mark this task blocked rather than completing it.
