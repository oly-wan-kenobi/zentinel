# Workflow: Task Done

Use this workflow only after Verifier reports green.

## Steps

1. Dispatch or simulate `Task Queue Manager`.
2. Update `tasks/status.json`.
3. Update `tasks/STATUS.md`.
4. Update `tasks/queue.json` and `tasks/QUEUE.md` if the task state changed there.
5. Record files changed, tests added, tests run, validator result, dogfooding implication, and follow-up tasks. These task-control edits are permitted only for the Task Queue Manager lifecycle transition.
6. Run `python3 scripts/validate_task_system.py`.

## Output

- synchronized task state
- completion evidence
- validator evidence
