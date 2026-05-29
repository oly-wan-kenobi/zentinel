# Codex Orchestrator Contract

The Orchestrator coordinates Codex roles while preserving zentinel's sequential task system. It is a dispatch contract, not an executable runtime.

The Orchestrator does not own product truth. It reads `AGENTS.md`, task state, active task files, `.agents/roles/*.md`, and the relevant `docs/` contracts, then routes work through the smallest safe role sequence.

## Required Inputs

- `AGENTS.md`
- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- active task file
- relevant `.agents/roles/*.md` profiles
- relevant `docs/` specs, ADRs, invariants, discipline rules, style rules, and harness rules
- current repository status

## State Machine

Task-control states are defined by `docs/AUTONOMOUS_AGENT_PROTOCOL.md`.

Task-control states are `queued`, `active`, `blocked`, `complete`, and `superseded`.

```text
queued -> active -> complete
                 \-> blocked
```

Artifact stages may include `implemented` and `verified`, but the Task Queue Manager must not write them to task-control files.

Only one task may be `active` pending completion at a time.

The Orchestrator may not advance a state unless the Task Queue Manager has synchronized both Markdown and JSON state files.

## Dispatch Order

For behavior-bearing tasks, use this order:

```text
Task Queue Manager
  -> Planner
  -> Test Author
  -> Test Reviewer
  -> Implementer
  -> Implementation Reviewer
  -> Verifier
  -> Task Queue Manager
```

Add specialized roles when required by task scope:

- `Property Test Agent` for invariant-heavy behavior.
- `Doctest Agent` for public documentation examples.
- `Mutation Agent` and `Mutation Triage Agent` for mutation-testable behavior.
- `Contract Editor` for public schema, CLI, config, report, ADR, task-system, or architecture contract edits. Public contract changes route through Contract Editor before review.
- `Architecture Reviewer` for architecture, public schema, backend, safety, or ADR changes.
- `Phase Planner` only for backlog or phase decomposition.

Contract Editor runs before Test Author when public contract changes define or change the tests' expected behavior; otherwise Test Author runs before implementation.

Architecture boundary checks are mandatory for tasks that add source files, change imports, touch deterministic core modules, modify adapters, or alter architecture contracts. Route those tasks through Architecture Reviewer unless the active task explicitly states the change is a documentation-only typo.

## Complexity Routing

This table mirrors `docs/PIPELINE_ESCALATION_POLICY.md`. Task Queue Manager and Planner steps still run when required by the task lifecycle or dispatch flow, but the class-specific minimum roles below must not drift from the escalation policy.

| Task class | Minimum roles |
| --- | --- |
| Low-risk | Test Author, Implementer, Verifier |
| Normal | Test Author, Test Reviewer, Implementer, Implementation Reviewer, Verifier |
| High-risk | Normal roles plus Property Test Agent or Mutation Agent as applicable |
| Compiler-internal | High-risk roles plus Architecture Reviewer |
| Architecture | Phase Planner, Contract Editor, Architecture Reviewer, Test Reviewer for executable contracts, Verifier |

When in doubt, choose the higher-risk route.

## Separation Rules

- Test Author must not implement production code.
- Implementer must not weaken approved tests.
- Implementation Reviewer must not approve broad scope expansion.
- Verifier must not edit implementation to make gates pass.
- Mutation Triage Agent must not call a survivor equivalent without a deterministic rule or accepted project policy.
- Task Queue Manager owns task state updates, not code quality approval.

If only one Codex agent is available, the same chat may execute multiple roles sequentially, but each role must produce separate evidence and must not erase failed evidence from earlier roles.

## Rejection Loop

When Test Reviewer rejects tests:

1. Preserve the rejection evidence.
2. Route back to Test Author with the exact required fixes.
3. Do not proceed to implementation until tests are approved.

When Implementation Reviewer rejects implementation:

1. Preserve the rejection evidence.
2. Route back to Implementer with the exact required fixes.
3. Do not weaken approved tests.

When Verifier fails:

1. Preserve command output and failing gate.
2. Route to the smallest responsible role.
3. Re-run only the relevant failing gates first, then the broader required gates.

Escalate to blocked only when `docs/AUTONOMOUS_AGENT_PROTOCOL.md` says the decision cannot be made autonomously.

## Context Packets

Fresh roles must receive a context packet containing:

- task id and task file
- current task state
- allowed and forbidden files
- relevant docs and ADRs
- relevant invariants, discipline rules, style rules, and harness rules
- required tests and acceptance criteria
- prior handoff artifacts
- exact next role objective

Context packets are governed by `docs/AGENT_CONTEXT_PACKETS.md`.

Before task `041`, context packets and handoffs are recorded in task status or completion summaries. After task `041`, durable context packets and handoffs are written under the active task's `artifacts/pipeline/<task-id>/**` directory.

## Handoffs

Every role produces a handoff with:

- role name
- files read
- files changed
- commands run
- evidence produced
- risks or uncertainties
- next role recommendation

Handoffs are governed by `docs/HANDOFF_CONTRACTS.md`.

## Stop Conditions

Stop implementation work and repair the operating state when:

- Markdown task state and JSON task state disagree.
- More than one task is active pending completion.
- A role needs a forbidden file.
- A required doc, ADR, invariant, or schema referenced by the task is missing.
- Approved tests would need to be weakened.
- A deterministic correctness decision would rely on AI output.
- The only safe path requires irreversible product judgment.

## Provider Boundary

This repository is Codex-only for development orchestration. Do not add Claude-specific directories, role metadata, slash commands, or settings. If a useful pattern comes from another project, translate the pattern into `.agents/`, `docs/`, `tasks/`, or `scripts/` without preserving provider-specific bindings.
