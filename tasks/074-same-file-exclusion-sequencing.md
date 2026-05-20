# 074 Same-File Exclusion Sequencing

Sequential guard: start this task only after task 073 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Move same-file Zig `test` declaration exclusion before the first stable mutator task so I-009 is established before candidate-emitting mutators exist.

## Scope

- Reorder task 019 before task 010 without renumbering task IDs.
- Update affected sequential guards, dependencies, and follow-up references.
- Add a structural validator guardrail for the same-file exclusion ordering.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/074-same-file-exclusion-sequencing.md`
- `tasks/000-project-bootstrap.md`
- `tasks/009-ast-candidate-ordering.md`
- `tasks/010-arithmetic-mutators.md`
- `tasks/018-report-renderers.md`
- `tasks/019-same-file-test-exclusion.md`
- `tasks/020-test-selection-same-file.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `docs/**`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail that rejects task 019 executing after task 010.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before reordering the affected tasks.
- Run `python3 scripts/validate_task_system.py` after queue, dependency, guard, and follow-up metadata are synchronized.

## Acceptance criteria

- Task 019 executes after task 009 and before task 010.
- Task 010 depends on task 019.
- Task 020 preserves dependencies on both report rendering and same-file exclusion prerequisites.
- The validator rejects future drift that schedules task 019 after candidate-emitting mutators.
- No product implementation files are changed.

## Non-goals

- Implementing same-file exclusion.
- Changing mutator behavior.
- Changing task IDs.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on the current order.
2. Move task 019 by assigning it a decimal execution order between tasks 009 and 010.
3. Update only the task metadata needed to preserve sequential execution and follow-up links.
4. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task ensures future dogfood candidates never include normal Zig test bodies by default.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
