# ADR-0004: Sequential task system is the autonomous work authority

**Status:** Accepted
**Date:** 2026-05-19

## Context

zentinel is intended to be implemented by autonomous sequential agents. Agents need a durable work queue, one active scope, synchronized human-readable and machine-readable state, and validation before task completion.

The repository already has `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, `tasks/status.json`, task files, and `scripts/validate_task_system.py`.

## Decision

The task system is the repository authority for autonomous implementation order and scope. Agents execute tasks sequentially, keep at most one task active, update Markdown and JSON state together, and run `python3 scripts/validate_task_system.py` before completion.

When a blocker can be resolved by adding a smaller prerequisite task, agents update the queue rather than asking the user by default.

## Alternatives Considered

- **Use chat history as the work queue.** Rejected because chat history is not durable enough for multiple agents or compaction.
- **Use Markdown only.** Rejected because machines need precise validation.
- **Use JSON only.** Rejected because humans need readable queue and status context.
- **Allow parallel active tasks.** Rejected until the pipeline has robust locking and artifact isolation.

## Consequences

**Positive.** Future agents can continue without human planning between tasks. Scope drift is easier to detect.

**Negative.** Small metadata updates are required for every task transition. The validator must evolve with the workflow.
