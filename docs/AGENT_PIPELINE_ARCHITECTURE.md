# Agent Pipeline Architecture

zentinel is developed by a sequential AI-agent pipeline. The pipeline is designed for compiler-adjacent engineering where small mistakes can corrupt deterministic behavior, source mapping, mutation semantics, or public contracts.

The pipeline is not product AI. It is the engineering operating system used to build zentinel.

Agent-facing role profiles and workflow runbooks live under `.agents/`. This document defines the stable architecture of the pipeline; `.agents/` defines how agents execute it. zentinel intentionally commits no `.claude/` directory.

## Core Architecture

```text
Phase Planner
  -> Task Queue Manager
  -> Orchestrator
  -> Stateless Subagents
```

Expanded flow:

```text
Roadmap + Specs
  -> Phase Planner
  -> Task Queue Manager
  -> Orchestrator
  -> Test Author
  -> Test Reviewer
  -> Contract Editor
  -> Implementer
  -> Implementation Reviewer
  -> Mutation Agent
  -> Mutation Triage Agent
  -> Property Test Agent
  -> Doctest Agent
  -> Verifier
  -> Task Queue Manager
```

## Pipeline Principles

- One repository task is active at a time.
- Tests are authored and reviewed before implementation.
- Implementers must not weaken approved tests.
- Mutation testing runs after implementation review and before final verification when the feature is mutation-testable.
- Property tests are required for invariant-heavy behavior.
- Doctests are required for public examples after doctest support exists.
- Fresh stateless subagents receive context packets, not implicit conversation history.
- Every step emits a structured handoff artifact.
- Deterministic verification is the only completion authority.

Before task `041`, context packets and handoffs are recorded in task status or completion summaries. After task `041`, durable pipeline handoffs and context packets live under `artifacts/pipeline/<task-id>/**`.

## Ownership Model

| Component | Owns | Does not own |
| --- | --- | --- |
| Phase Planner | Phase decomposition, task sizing, dependency shape. | Task execution. |
| Task Queue Manager | Queue state, active lock, completion transitions. | Code review. |
| Orchestrator | Context packets, subagent routing, escalation decisions. | Direct implementation unless no subagent path exists. |
| Contract Editor | Public contract changes, schema/docs alignment, ADR/task-scope ownership notes. | Runtime implementation. |
| Subagents | Role-specific artifacts and bounded edits. | Queue state ownership. |
| Verifier | Final command evidence and reproducibility check. | Changing implementation to pass tests. |

## State Ownership

Persistent state lives in repository files:

- `tasks/queue.json`
- `tasks/status.json`
- `tasks/QUEUE.md`
- `tasks/STATUS.md`
- `artifacts/pipeline/<task-id>/` after task `041`

The Orchestrator may hold temporary context, but durable state must be written to task status files before task `041` and to artifacts plus task status files after task `041`.

## Verification Boundary

Subagents may report local success. Only the Verifier can approve completion evidence; artifact stages do not change task-control state.

The Verifier checks:

- required unit tests
- property tests
- doctests
- mutation gate
- snapshot verification
- dogfood checks when required
- task-system validation

## Complexity-Adaptive Depth

| Task class | Required pipeline |
| --- | --- |
| Low-risk task | Test Author, Implementer, Verifier. |
| Normal task | Test Author, Test Reviewer, Implementer, Implementation Reviewer, Verifier. |
| High-risk task | Normal pipeline plus Property Test Agent or Mutation Agent as applicable. |
| Compiler-internal task | High-risk pipeline plus Architecture Reviewer and stricter source-mapping review. |
| Architecture task | Phase Planner, Contract Editor, Architecture Reviewer, Test Reviewer for executable contracts, Verifier. |

The Orchestrator classifies task complexity before spawning subagents.

Use both specialized roles only when both triggers apply.

Public contract changes route through Contract Editor before Architecture Reviewer or Implementation Reviewer approval. This keeps the authoring role separate from the review role for schema, CLI, config, report, ADR, task-system, and architecture contracts.

Contract Editor runs before Test Author when public contract changes define or change the tests' expected behavior; otherwise Test Author runs before implementation.

## Canonical Mutation-Aware Flow

```text
Tests
  -> Implementation
  -> Review
  -> Mutation Gate
  -> Survivor Triage
  -> Final Verification
```

Mutation gate does not replace unit, property, or doctest verification. It checks whether tests and executable docs detect meaningful behavioral changes.

## Determinism Requirements

The pipeline must preserve deterministic:

- task state transitions
- artifact names
- command lists
- verification ordering
- mutation report ordering
- property test seeds
- doctest case IDs
- snapshot output

Subagent ordering must not affect final repository state.
