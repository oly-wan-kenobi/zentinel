# Workflow: Task Plan

Use this workflow when preparing the next queued task for implementation.

## Steps

1. Run `python3 scripts/validate_task_system.py`.
2. Read `tasks/status.json` and confirm no task is active.
3. Resolve the first dependency-ready queued task by execution order from `tasks/queue.json`.
4. Read the task file and required docs from `AGENTS.md`.
5. Dispatch or simulate `Task Queue Manager` to mark the task active.
6. Dispatch or simulate `Planner`.
7. Record the plan, risks, applicable contracts, and required tests in the task handoff location. Before task `041`, use task status or the completion summary for equivalent pre-artifact handoff fields; after task `041`, use the task-scoped artifact path under `artifacts/pipeline/<task-id>/`.

## Stop Conditions

- Markdown and JSON task state disagree.
- A dependency is incomplete.
- The task requires a forbidden file.
- The task is too broad for one bounded implementation session.

## Output

- active task state
- planner handoff
- validator evidence
