# Agent Guide

This repository is designed for sequential AI-agent development. Agents must preserve architectural direction, keep tasks small, and leave the repository easier for the next agent.

## Operating Rules

1. Only one task is active at a time.
2. Tasks are executed by queue execution order. A task's explicit `order` key may differ from its stable numeric ID when a prerequisite is inserted.
3. Read this guide, `docs/VISION.md`, `docs/NON_GOALS.md`, `docs/GLOSSARY.md`, `docs/ARCHITECTURE.md`, `docs/TDD_POLICY.md`, `docs/INVARIANTS.md`, `docs/DISCIPLINE.md`, `docs/STYLE.md`, and the active task before changing files.
4. Write or update tests before implementation.
5. Modify only files allowed by the active task, except Task Queue Manager lifecycle edits to task-control files, row-scoped gap registry updates under `tests/coverage-gaps/<registry>.v1.json`, and task-scoped pipeline artifacts after task `041` is complete.
6. Do not perform broad refactors.
7. Do not implement future phases early.
8. Preserve deterministic behavior.
9. Update `tasks/STATUS.md` and `tasks/status.json` when a task is completed or blocked.
10. Keep AI advisory behavior separate from deterministic core behavior.
11. Run `python3 scripts/validate_task_system.py` before and after task state changes.
12. Treat public documentation examples as future executable contracts and use doctest block formats when adding examples.
13. Follow the Codex operating layer in `.agents/README.md` and `.agents/ORCHESTRATOR.md` for every non-trivial task.
14. Update `tests/coverage-gaps/` when adding or covering invariants, failure modes, stable mutators, or schema contracts.
15. Use ADRs under `docs/adr/` for foundational decisions that future agents should not re-litigate.
16. Do not add `.claude/`; translate provider-specific agent patterns into Codex-neutral `.agents/`, `docs/`, `tasks/`, or `scripts/`.

## Task Lifecycle

```text
queued -> active -> implemented -> verified -> complete
                       └──── blocked
```

An agent starts work by:

- selecting the first dependency-ready queued task by execution order in `tasks/QUEUE.md`
- confirming it is also the first dependency-ready queued task in `tasks/queue.json`
- reading the selected task file and required docs from `AGENTS.md`
- marking it active in `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`

An agent completes work by:

- recording tests run
- recording pipeline handoff artifacts when the active task requires them
- recording files changed
- recording any follow-up task discovered
- updating gap registries when coverage changed
- marking the task complete
- running `python3 scripts/validate_task_system.py`

## Agent Pipeline

Codex role profiles and workflow runbooks live under `.agents/`. The `docs/` files define stable project contracts; `.agents/` defines how Codex agents operate against those contracts.

The default engineering flow is:

```text
Phase Planner
  -> Task Queue Manager
  -> Orchestrator
  -> Stateless Subagents
```

Task execution then follows the smallest pipeline depth allowed by `docs/PIPELINE_ESCALATION_POLICY.md`.

Normal behavior-bearing tasks use:

```text
Test Author
  -> Test Reviewer
  -> Implementer
  -> Implementation Reviewer
  -> Verifier
```

High-risk, compiler-internal, public-contract, property-heavy, or mutation-sensitive tasks add specialized roles:

- `Mutation Agent`
- `Mutation Triage Agent`
- `Property Test Agent`
- `Doctest Agent`
- `Architecture Reviewer`

Agents in one role must not silently perform another role's authority. An Implementer may run tests locally, but may not approve weakened tests. A Mutation Triage Agent may classify survivor evidence, but may not decide equivalence without a documented deterministic rule or human-approved project policy.

## Sequential Development Contract

Agents must assume future agents depend on the current task's boundaries. Do not change task order without updating `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`.

When a task reveals a missing prerequisite:

1. Do not silently expand scope.
2. Add a focused follow-up task or mark the current task blocked.
3. Keep any partial code behind tests or revert your own incomplete edits.
4. Use `docs/AUTONOMOUS_AGENT_PROTOCOL.md` to resolve normal blockers without waiting for a human.

## File Modification Discipline

Every task lists allowed and forbidden files.

The Markdown task file is human-readable. `tasks/queue.json` is the machine-readable enforcement target. Keep both synchronized.

Allowed means:

- the task may edit those files if needed
- edits must still be minimal

Forbidden means:

- do not edit the file
- do not reformat the file
- do not update snapshots owned by future tasks

If a forbidden file appears necessary, block the task and explain why.

Task-control files are the only built-in exception. The Task Queue Manager may update `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`, and may create or rename task markdown files under `tasks/`, for state transitions, blocker insertion, queue reordering, and validator-required synchronization even when the active task does not list them as allowed files.

When inserting a prerequisite, keep existing task IDs stable. Assign the prerequisite the next unused three-digit ID, place it before the blocked task with an `order` key, update dependencies, and run the validator before implementation resumes.

Gap registries are a row-scoped built-in exception. When a task adds, changes, or covers a documented invariant, failure mode, stable mutator, or schema contract, it may update only the matching row or newly required row in `tests/coverage-gaps/<registry>.v1.json` even if that file is not listed in the task's allowed files. This exception never permits unrelated registry cleanup, docs edits, schema edits, source edits, or task-scope expansion.

After task `041` is complete, pipeline artifacts are a second narrow exception. A role may create or update files only under `artifacts/pipeline/<active-task-id>/**` for the active task's context packets, handoffs, reviews, verification reports, or other audit artifacts defined by `docs/PIPELINE_ARTIFACTS.md`. This exception never authorizes changes to source, tests, docs, schemas, task state, or another task's artifact directory.

## Commit Hygiene

Each completed task should be independently understandable:

- one task per commit when commits are requested
- commit message starts with the task number
- generated artifacts are committed only if they are documented outputs
- no unrelated formatting churn

Example:

```text
004 add config validation tests
```

## Required Status Entry

Each completed task entry in `tasks/STATUS.md` must include:

- task ID and title
- date completed
- files changed
- tests added
- tests run
- deterministic behavior affected
- dogfooding implication
- known follow-ups

## AI Usage By Agents

Agents may use AI reasoning to plan, explain, or draft. Agents must not use AI as the authority for:

- whether a mutant is killed or survived
- whether a compile error is expected
- whether a mutant is equivalent
- whether a test can be skipped
- whether a report schema change is compatible

The repository contracts are the authority.

## Documentation Update Rules

Update docs when:

- a public CLI option changes
- a config key changes
- a report field changes
- an AI JSON contract changes
- a backend stability level changes
- a mutator's allowed/forbidden contexts change
- a doctest block format, execution rule, or matching rule changes
- an invariant, failure mode, ADR, discipline rule, or style rule changes

When docs add a new invariant, failure mode, mutator, or schema contract, update the matching gap registry under `tests/coverage-gaps/`.

## Doctest Authoring Rules

Future agents writing public docs must follow `docs/DOCTEST_BLOCK_FORMATS.md`.

Rules:

- CLI examples intended to be executable use `bash cli`.
- Config examples use `toml config` or `toml config_fail`.
- Expected CLI output uses `text output` or `json expected`.
- Mutator transformation examples use `zig before` and `zig after`.
- Examples must be deterministic and snapshot-friendly.
- Do not use prose as the only behavioral contract when a doctest block can express it.
- Do not update expected output blocks without reviewing the semantic diff.

Do not update docs merely to describe local implementation details that are not contractually relevant.

## Handoff Quality

A good handoff lets the next agent work without re-investigating:

- final status is accurate
- tests are passing or failures are explicitly documented
- no hidden local commands are required
- follow-up tasks are precise
- no future phase was partly implemented without tests
- required handoff fields match `docs/HANDOFF_CONTRACTS.md`
- context packet references are current and scoped to the active task

Pipeline handoff artifacts should be written under `artifacts/pipeline/<task-id>/` once that artifact directory is introduced. Until then, agents must include the same fields in `tasks/STATUS.md` or the task completion summary.

Pre-artifact completion summaries must include:

- logical role performed
- files read
- files changed
- commands run and results
- evidence produced
- risks, assumptions, or skipped gates
- next role or next task recommendation

Task `041` is the cutover point for durable handoff artifacts. After it is complete, non-trivial tasks must use the artifact paths specified by `docs/HANDOFF_CONTRACTS.md` and `docs/PIPELINE_ARTIFACTS.md`. JSON handoffs are canonical; Markdown summaries are optional companion artifacts only.

## Pipeline Reference Map

| Need | Read |
| --- | --- |
| Codex agent operating layer | `.agents/README.md` |
| Orchestrator dispatch | `.agents/ORCHESTRATOR.md` |
| Role operating profiles | `.agents/roles/` |
| Workflow runbooks | `.agents/workflows/` |
| Stable role responsibility spec | `docs/AGENT_ROLE_SPEC.md` |
| Canonical terminology | `docs/GLOSSARY.md` |
| Scope boundaries | `docs/NON_GOALS.md` |
| Invariants | `docs/INVARIANTS.md` |
| Engineering discipline | `docs/DISCIPLINE.md` |
| Style rules | `docs/STYLE.md` |
| Harness requirements | `docs/HARNESS.md` |
| Failure catalog | `docs/FAILURE_MODES.md` |
| Architecture decisions | `docs/adr/README.md` |
| Coverage gaps | `docs/GAP_REGISTRIES.md` |
| Task state transitions | `docs/TASK_LIFECYCLE.md` |
| Orchestrator duties | `docs/ORCHESTRATION_SPEC.md` |
| Handoff format | `docs/HANDOFF_CONTRACTS.md` |
| Context packet format | `docs/AGENT_CONTEXT_PACKETS.md` |
| Verification order | `docs/VERIFICATION_PIPELINE.md` |
| Mutation gate | `docs/MUTATION_GATE_POLICY.md` |
| Escalation rules | `docs/PIPELINE_ESCALATION_POLICY.md` |
| Failure recovery | `docs/FAILURE_RECOVERY.md` |
| Sequential locking | `docs/SEQUENTIAL_EXECUTION_POLICY.md` |
