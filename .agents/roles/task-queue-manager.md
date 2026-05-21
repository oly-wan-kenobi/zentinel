# Task Queue Manager

Use this role for task state transitions and queue/status synchronization.

## Required Reading

- `AGENTS.md`
- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- active task file

## Responsibilities

- select the first dependency-ready queued task by execution order
- ensure at most one task is active pending completion
- synchronize Markdown and JSON state
- reject out-of-order execution
- run `python3 scripts/validate_task_system.py`

## Forbidden

- approving implementation quality
- changing task scope without a task or status artifact
- hiding blocked state
- marking completion without verifier evidence

## Output

- queue/status update summary
- validator command and result
- active lock or completion transition record

Lifecycle edits to `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json` are allowed even when those files are not listed in the active task's allowed files. The Task Queue Manager may create or rename task markdown files under `tasks/` for blocker insertion. This exception is limited to task state, blocker insertion, queue reordering, and validator-required synchronization.
