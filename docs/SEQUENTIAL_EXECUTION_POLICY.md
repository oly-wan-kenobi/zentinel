# Sequential Execution Policy

zentinel prioritizes sequential task execution to minimize merge conflicts and architectural drift.

## Active Task Lock

Only one task may be active.

Lock state lives in:

- `tasks/queue.json`
- `tasks/QUEUE.md`
- `tasks/status.json`
- `tasks/STATUS.md`
- after task `041`, `artifacts/pipeline/<task-id>/locks/active-task-lock.json`

Before task `041`, the synchronized task files are the canonical active-task lock and equivalent context evidence is recorded in task status or completion summaries. After task `041`, no subagent may start implementation unless the active task lock also matches its context packet and `locks/active-task-lock.json`.

## Markdown and JSON Synchronization

The Markdown and JSON task-control files are two views of one state and must agree before any state change is accepted:

- exactly one task may have `state` `active` in `tasks/queue.json`; `tasks/QUEUE.md` must show the same state for that task id.
- `tasks/status.json` `active_task` must equal the single active task id, or be `null` when no task is active; `tasks/STATUS.md` Active task must match.
- while a task is active, `next_task` equals the active task id; with no active task, `next_task` is the first dependency-ready queued task by execution order, and `tasks/STATUS.md` Next task must match.
- a task may not be active while any of its dependencies is still `queued` or `blocked` (no skip-ahead).

A snapshot that violates any of these rules is rejected; the canonical violation is two tasks marked `active` at once.

## Stale Lock Recovery

After task `041`, the active task also owns `artifacts/pipeline/<task-id>/locks/active-task-lock.json`. A lock is stale when:

- the lock `task_id` does not equal `tasks/status.json` `active_task`, or
- a lock artifact exists while `active_task` is `null`, or
- the lock `state` is not `active`.

Recovery is deterministic and auditable:

1. Detect the stale lock during the final artifact audit or task activation.
2. Confirm the task-control files (`tasks/queue.json`, `tasks/QUEUE.md`, `tasks/status.json`, `tasks/STATUS.md`) agree on the true active task; the synchronized task-control files are authoritative over a stale lock.
3. Replace the lock with one whose `task_id`, `queue_order`, and `context_packet` match the authoritative active task, or remove it when no task is active.
4. Record the recovery in the verifier report `residual_risk` or the completion summary so the action is auditable.

A stale lock blocks completion until recovery runs; lock failures follow `docs/FAILURE_RECOVERY.md`.

## Queue Semantics

- Every task entry in `tasks/queue.json` contains an explicit `order` key.
- tasks execute by the queue's execution order, not by stable task ID
- dependencies must be complete
- reordering requires queue and status updates
- blocked tasks create prerequisite tasks rather than hidden side work
- A different task must not be activated across uncommitted prior-task changes unless a validator-readable clean handoff baseline is recorded.

## Branch Ownership

When branches are used:

- one branch per active task
- branch name uses an agent-task prefix such as `agent/<task-id>`
- do not mix multiple task implementations on one branch
- merge only after verification passes

## Conflict Prevention

Tasks must define narrow allowed files. If two future tasks need the same file, the earlier task owns only the minimal change needed for its acceptance criteria.

Agents must not:

- batch unrelated tasks
- refactor broad modules opportunistically
- edit future task snapshots
- change queue state without validation

## Merge Ordering

Completed tasks merge in queue order. If a later task is implemented experimentally, it cannot merge before earlier dependencies are complete and verified.
