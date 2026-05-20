# 072 Prebootstrap Sequencing and Contract Cleanup

Sequential guard: start this task only after task 071 is complete in `tasks/STATUS.md`. This task has execution order `000.0.3` and must complete before task `000`.

## Goal

Resolve the remaining pre-bootstrap sequencing and documentation inconsistencies that could mislead autonomous agents before implementation starts.

## Scope

- Prevent dependency-only task selection from starting task `064` before earlier execution-order tasks.
- Add validator coverage for direct previous-task dependency links so dependency-ready scans cannot bypass queue order.
- Align harness/report wording around where safety mode is recorded.
- Fix roadmap scaffold wording so Phase 0 does not imply unowned `examples/` or `tools/` directory creation.
- Refresh stale invariant gap wording and handoff-roadmap wording found during the analysis.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/064-pipeline-artifact-ci-integration.md`
- `tasks/072-prebootstrap-sequencing-and-contract-cleanup.md`
- `tasks/000-project-bootstrap.md`
- `scripts/validate_task_system.py`
- `docs/HARNESS.md`
- `docs/ROADMAP.md`
- `tests/coverage-gaps/invariants.v1.json`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `docs/MUTATOR_SPEC.md`
- `.claude/**`

## Required tests

- Add a failing structural validator guardrail proving a queued task cannot become dependency-ready before the immediately preceding non-superseded execution-order task is complete.
- Run `python3 scripts/validate_task_system.py` before and after fixing the task `064` dependency.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax validation for edited JSON files.
- Run `git diff --check`.

## Acceptance criteria

- Task `064` cannot become dependency-ready before task `062` completes.
- Task `000` names task `072` as its immediate prerequisite.
- The validator rejects future queue entries that omit a direct dependency on the immediately preceding non-superseded execution-order task.
- Harness and report contracts no longer disagree about command-level mode evidence.
- Roadmap Phase 0 no longer implies unowned scaffold directories.
- Stale invariant and handoff-roadmap wording is aligned with current contracts.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing zentinel behavior.
- Creating Zig source, build files, examples, or tools.
- Changing report schemas.
- Reordering product implementation tasks beyond the task `064` dependency clarification.

## Suggested implementation approach

1. Insert this task after task `071` and mark it active.
2. Add the validator guardrail first and confirm it fails on the current task `064` dependency shape.
3. Update task `064` to depend on the preceding execution-order task.
4. Patch only the inconsistent docs and registry row.
5. Complete this task and leave task `000` as the next dependency-ready task.

## Dogfooding implications

No dogfood run is expected because no runtime behavior exists yet. The change strengthens future pipeline and CI dogfood task ordering.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
