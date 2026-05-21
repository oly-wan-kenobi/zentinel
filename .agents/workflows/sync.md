# Workflow: Sync

Use this workflow when repository state and task metadata may have drifted.

## Steps

1. Read `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`.
2. Run `python3 scripts/validate_task_system.py`.
3. If validation fails, repair task metadata before implementation work continues.
4. Confirm `status.next_task` is the current active task or the first dependency-ready queued task by execution order.
5. Confirm active, blocked, completed, and superseded states match in Markdown and JSON.
6. Record warnings that require human judgment instead of silently rewriting history.

## Output

- synchronization summary
- validator result
- warnings or repairs applied
