# Orchestration Specification

The Orchestrator coordinates role execution while preserving sequential task ownership.

## Inputs

- active task markdown
- `tasks/queue.json`
- `tasks/status.json`
- relevant specs under `docs/`
- prior pipeline artifacts for the task
- repository status

## Outputs

- context packets
- role assignments
- handoff artifacts
- escalation decisions
- final verification request

Before task `041`, context packets and handoffs are recorded in task status or completion summaries. After task `041`, they are persisted under `artifacts/pipeline/<task-id>/**`.

## Orchestration Steps

1. Validate task system.
2. Acquire active task lock through Task Queue Manager.
3. Classify task complexity.
4. Build context packets.
5. Run Test Author.
6. Run Test Reviewer.
7. Run Contract Editor before implementation when public contracts, schemas, ADRs, task-system contracts, or architecture docs change.
8. Run Implementer only after tests and contract edits are approved for implementation.
9. Run Implementation Reviewer.
10. Run property, doctest, and mutation agents as required.
11. Run Verifier.
12. Update queue/status and artifacts.

## State Ownership

The Orchestrator may not rely on chat history as state. It must persist key decisions in:

```text
artifacts/pipeline/<task-id>/orchestration.md
artifacts/pipeline/<task-id>/context/*.json
artifacts/pipeline/<task-id>/handoffs/*.json
```

Those artifact paths are required only after task `041` introduces durable pipeline artifacts.

Markdown handoff summaries may be written next to JSON handoffs, but JSON handoffs are the canonical machine-readable state.

## Subagent Rules

Fresh subagents receive context packets and produce artifacts. They should not assume access to previous conversation beyond packet content.

Subagents must:

- respect allowed files
- avoid broad refactors
- report uncertainty
- include commands run
- avoid changing task state directly unless assigned Task Queue Manager role

## Complexity Classification

| Class | Trigger |
| --- | --- |
| Low-risk | Docs-only or narrow tests with no public contract change. |
| Normal | Single-module behavior with clear tests. |
| High-risk | Shared model, runner, cache, report, mutation semantics, or public schema. |
| Compiler-internal | AST/ZIR/AIR, source mapping, Zig version coupling, or safety-mode semantics. |
| Architecture | Roadmap, public contracts, task system, or module boundaries. |

The Orchestrator chooses the highest applicable class.

Low-risk tasks may omit Test Reviewer and Implementation Reviewer only when `docs/PIPELINE_ESCALATION_POLICY.md` allows it. Architecture tasks that edit contracts route through Planner or Phase Planner for planning, Contract Editor for the edit step, and Architecture Reviewer for review. Public contract changes route through Contract Editor before review.
