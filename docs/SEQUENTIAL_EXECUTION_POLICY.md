# Sequential Execution Policy

zentinel prioritizes sequential task execution to minimize merge conflicts and architectural drift.

## Active Task Lock

Only one task may be active.

Lock state lives in:

- `tasks/queue.json`
- `tasks/QUEUE.md`
- `tasks/status.json`
- `tasks/STATUS.md`
- after task `041`, the task-scoped pipeline artifact lock record

Before task `041`, the synchronized task files are the canonical active-task lock and equivalent context evidence is recorded in task status or completion summaries. After task `041`, no subagent may start implementation unless the active task lock also matches its context packet and task-scoped pipeline artifact lock record.

## Queue Semantics

- tasks execute by the queue's execution order, using an explicit `order` key when it differs from the task ID
- dependencies must be complete
- reordering requires queue and status updates
- blocked tasks create prerequisite tasks rather than hidden side work

## Branch Ownership

When branches are used:

- one branch per active task
- branch name starts with `codex/`
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
