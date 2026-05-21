# Workflow: Task Done

Use this workflow only after Verifier reports green.

## Steps

1. Dispatch or simulate `Task Queue Manager`.
2. Record files changed, tests added, tests run, validator result, dogfooding implication, and follow-up tasks while the task remains current. These task-control edits are permitted only for the Task Queue Manager lifecycle transition.
3. Run `python3 scripts/validate_task_system.py` while the task is still active before changing queue state to `complete`; this preserves changed-file scope validation against the active task.
4. Update `tasks/status.json`.
5. Update `tasks/STATUS.md`.
6. Update `tasks/queue.json` and `tasks/QUEUE.md`; then mark the task `complete`.
7. Run `python3 scripts/validate_task_system.py` again after the complete-state transition to prove synchronized queue/status state.
8. Establish the clean handoff boundary before any different task is activated. If completed-task changes remain uncommitted, record `clean_handoff_baseline` with the completed task id, source commit, and per-file SHA-256 entries for non-task-control dirty files that make prior task changes explicit to active-scope validation. After committing completed-task changes, clear `clean_handoff_baseline` to `null`.

## Output

- synchronized task state
- completion evidence
- validator evidence
