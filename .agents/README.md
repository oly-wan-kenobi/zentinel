# zentinel Codex Agent Layer

This directory contains the Codex-only operating layer for building zentinel with autonomous agents.

It is not a second product documentation tree. Product contracts, architecture, invariants, style, harness rules, failure modes, schemas, and ADRs stay under `docs/`. This directory explains how Codex agents should dispatch roles, route handoffs, and run task workflows against those contracts.

Do not add `.claude/` to this repository. zentinel is developed by Codex, and agent instructions must remain Codex-neutral instead of binding the project to Claude Code commands, model names, or permission files.

## Directory Map

```text
.agents/
  README.md
  ORCHESTRATOR.md
  roles/
    phase-planner.md
    task-queue-manager.md
    planner.md
    test-author.md
    test-reviewer.md
    implementer.md
    implementation-reviewer.md
    mutation-agent.md
    mutation-triage-agent.md
    property-test-agent.md
    doctest-agent.md
    architecture-reviewer.md
    verifier.md
  workflows/
    task-plan.md
    task-test.md
    task-implement.md
    task-verify.md
    task-done.md
    sync.md
```

## Authority Boundary

Use this authority order when operating as a Codex agent:

1. System, developer, and direct user instructions.
2. `AGENTS.md`.
3. `tasks/queue.json`, `tasks/status.json`, `tasks/QUEUE.md`, and `tasks/STATUS.md`.
4. The active task file.
5. `.agents/ORCHESTRATOR.md` and the relevant `.agents/roles/*.md` profile.
6. Specification documents under `docs/`.
7. Existing implementation patterns.

If a role profile conflicts with a project contract under `docs/`, stop and repair the conflict instead of choosing whichever file is more convenient.

## What Belongs Here

- role operating profiles
- workflow runbooks
- separation-of-duty rules
- context packet loading rules
- handoff routing
- rejection and escalation loops
- audit artifact layout

## What Does Not Belong Here

- product requirements
- report, config, or AI schema definitions
- invariant definitions
- style and discipline rules
- ADR decisions
- runtime source code
- provider-specific command files such as `.claude/commands`

## Codex Usage

When Codex subagents are available and the environment explicitly permits them, dispatch separate agents for roles that must not share authority, especially Test Author versus Implementer and Reviewer versus Implementer.

When only one Codex agent is available, preserve the same logical separation by running the roles sequentially and recording each role's evidence in the task status or pipeline artifacts. A single agent may execute multiple roles, but it must not use implementation knowledge to weaken tests or review its own changes without a separate review pass.

## Role Summary

| Role | Trigger | Output |
| --- | --- | --- |
| Phase Planner | phase or backlog decomposition is needed | bounded task plan and dependency shape |
| Task Queue Manager | task state changes are needed | synchronized Markdown and JSON task state |
| Planner | task is selected for work | concrete implementation plan and risk notes |
| Test Author | task plan is ready | failing tests, fixtures, doctests, or property cases |
| Test Reviewer | tests have been authored | approval or required test fixes |
| Implementer | tests are approved | scoped implementation that passes approved tests |
| Implementation Reviewer | implementation exists | code review verdict and required fixes |
| Mutation Agent | task is mutation-testable | deterministic mutation report |
| Mutation Triage Agent | mutation survivors exist | survivor classification with evidence |
| Property Test Agent | invariants require generated coverage | property tests and seed policy evidence |
| Doctest Agent | public examples change | executable docs examples and snapshots |
| Architecture Reviewer | architecture or public contract changes | architecture drift review and ADR needs |
| Verifier | task is ready to close | reproducible command evidence and final verdict |

## Audit Artifacts

Once `artifacts/pipeline/` exists, every non-trivial task should write durable evidence under:

```text
artifacts/pipeline/<task-id>/
  orchestration.md
  context/
  handoffs/
  reviews/
  verification/
```

Until that artifact tree exists, record equivalent evidence in `tasks/STATUS.md`, `tasks/status.json`, and the completion summary.

After task `041` introduces the artifact tree, writes under `artifacts/pipeline/<active-task-id>/**` are a task-scoped audit exception to normal allowed-file lists. That exception is limited to pipeline evidence and never authorizes source, docs, tests, schema, task-state, or another task's artifact changes.

Pre-artifact handoffs must include:

- logical role performed
- files read
- files changed
- commands run and results
- evidence produced
- risks, assumptions, or skipped gates
- next role or next task recommendation

Task `041` introduces the durable handoff artifact structure. After that task is complete, non-trivial tasks must use the artifact paths defined there instead of relying only on status summaries. JSON handoffs are the canonical machine-readable artifacts; Markdown summaries may accompany them but must not replace them.
