# Pipeline Artifacts

Pipeline artifacts preserve context across stateless agents and long-running development.

## Artifact Root

```text
artifacts/pipeline/<task-id>/
```

Subdirectories:

```text
context/
locks/
handoffs/
reviews/
tests/
property/
doctest/
mutation/
verification/
decisions/
```

## Naming Conventions

```text
context/<role>.json
locks/active-task-lock.json
handoffs/<step>-<role>.json
reviews/test-review.md
reviews/implementation-review.md
mutation/report.json
mutation/triage.md
property/report.json
doctest/report.json
verification/report.md
verification/report.json
decisions/ADR-<task-id>-<short-name>.md
```

JSON handoffs are canonical. Optional Markdown summaries may use the same handoff basename with `.md`, but they are companion notes and cannot replace the JSON artifact required by `docs/HANDOFF_CONTRACTS.md`.

Required handoff basenames are deterministic:

```text
00-orchestrator.json
01-phase-planner.json
02-task-queue-manager-start.json
03-planner.json
04-test-author.json
05-test-reviewer.json
06-implementer.json
07-implementation-reviewer.json
08-mutation-agent.json
09-mutation-triage-agent.json
10-property-test-agent.json
11-doctest-agent.json
12-architecture-reviewer.json
13-verifier.json
14-task-queue-manager-complete.json
```

## Active Lock Artifact

After task `041`, each active task writes exactly one active lock artifact at:

```text
artifacts/pipeline/<task-id>/locks/active-task-lock.json
```

The artifact records:

- `schema_version`: constant `zentinel.pipeline.active_lock.v1`
- `task_id`
- `state`
- `queue_order`
- `queue_file`
- `status_file`
- `context_packet`
- `created_by_role`
- `source_commit`
- `working_tree_state`

The active lock artifact is evidence that the task-control files, context packet, and pipeline artifact directory all name the same active task. It does not replace `tasks/queue.json`, `tasks/QUEUE.md`, `tasks/status.json`, or `tasks/STATUS.md`; those synchronized task files remain the canonical queue state.

## Retention Policy

- Keep artifacts for completed tasks that affect public contracts, mutation semantics, reports, cache, runner, doctests, or AI contracts.
- Low-risk docs-only artifacts may be summarized in status after completion.
- Do not store secrets, raw home paths, or full temp workspaces.

## Traceability

Every artifact must include:

- task ID
- role
- timestamp or normalized run label
- command evidence when applicable
- source commit or working-tree state when available

Artifacts should be referenced from `tasks/STATUS.md` and `tasks/status.json`. After task `041`, `completion_evidence.artifacts` lists the canonical artifact paths required or produced by the completed task so fresh agents can locate durable evidence without parsing Markdown prose.
