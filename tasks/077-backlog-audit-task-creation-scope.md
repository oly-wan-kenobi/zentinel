# 077 Backlog Audit Task Creation Scope

Sequential guard: start this task only after task 076 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Clarify task 025's authority to create a new task file when the backlog audit finds a concrete missing implementation task.

## Scope

- Update task 025 allowed files and scope language so audit-discovered task creation is permitted.
- Keep the permission limited to task metadata and next-unused task files.
- Add a structural validator guardrail for task 025's task-creation scope.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/077-backlog-audit-task-creation-scope.md`
- `tasks/000-project-bootstrap.md`
- `tasks/025-autonomous-backlog-audit.md`
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

- Add a failing validator guardrail that rejects task 025 without an explicit new-task-file allowance.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating task 025.
- Run `python3 scripts/validate_task_system.py` after task 025 is aligned.

## Acceptance criteria

- Task 025 may create a next-unused `tasks/[0-9][0-9][0-9]-*.md` file only when the audit finds a concrete missing task.
- Task 025 still may not edit product source, tests, schemas, scripts, or docs.
- The validator preserves task 025's explicit task-creation allowance.
- No product implementation files are changed.

## Non-goals

- Performing the task 025 backlog audit early.
- Creating any new product backlog task beyond this prerequisite.
- Relaxing allowed-file discipline for ordinary implementation tasks.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on task 025's current allowed-file list.
2. Add a narrow task-file glob and scope sentence to task 025.
3. Keep forbidden files unchanged.
4. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task prevents a future audit agent from blocking when the correct autonomous action is to create a concrete missing task.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
