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

Task states are defined by `docs/AUTONOMOUS_AGENT_PROTOCOL.md`:

```text
queued -> active -> implemented -> verified -> complete
                 \-> blocked
```

Only one task may be `active`, `implemented`, or `verified` pending completion at a time.

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
- `Architecture Reviewer` for architecture, public schema, backend, safety, or ADR changes.
- `Phase Planner` only for backlog or phase decomposition.

## Complexity Routing

| Task class | Minimum roles |
| --- | --- |
| Low-risk docs-only | Planner, Verifier |
| Low-risk test-only | Test Author, Verifier |
| Normal behavior | Planner, Test Author, Test Reviewer, Implementer, Implementation Reviewer, Verifier |
| High-risk behavior | Normal behavior roles plus Property Test Agent or Mutation Agent as applicable |
| Compiler-internal | High-risk behavior roles plus Architecture Reviewer |
| Architecture or governance | Planner, Architecture Reviewer, Verifier |

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
- More than one task is active, implemented, or verified pending completion.
- A role needs a forbidden file.
- A required doc, ADR, invariant, or schema referenced by the task is missing.
- Approved tests would need to be weakened.
- A deterministic correctness decision would rely on AI output.
- The only safe path requires irreversible product judgment.

## Provider Boundary

This repository is Codex-only for development orchestration. Do not add Claude-specific directories, role metadata, slash commands, or settings. If a useful pattern comes from another project, translate the pattern into `.agents/`, `docs/`, `tasks/`, or `scripts/` without preserving provider-specific bindings.
