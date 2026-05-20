# Autonomous Agent Protocol

This protocol turns zentinel's documentation into an executable operating system for AI agents. The goal is end-to-end implementation without a human coordinator.

## Authority Order

When instructions conflict, use this order:

1. System, developer, and direct user instructions.
2. `AGENTS.md`.
3. Machine-readable task state in `tasks/queue.json` and `tasks/status.json`.
4. The active task markdown file.
5. Codex operating contracts under `.agents/`.
6. Specification docs under `docs/`.
7. Existing implementation patterns.

If machine-readable state and Markdown disagree, stop implementation work and repair state synchronization first.

zentinel uses Codex-only development orchestration. Do not create `.claude/` or provider-specific command/profile files. Translate useful external agent patterns into `.agents/`, `docs/`, `tasks/`, or `scripts/`.

## Standard Agent Loop

1. Run `python3 scripts/validate_task_system.py`.
2. Read `tasks/status.json`.
3. If no task is active, select the first dependency-ready queued task from `tasks/queue.json` by execution order. Every task entry in `tasks/queue.json` contains an explicit `order` key.
4. Read the selected task file and required docs from `AGENTS.md` before marking it active.
5. Mark it `active` in `tasks/queue.json`, `tasks/QUEUE.md`, `tasks/status.json`, and `tasks/STATUS.md`.
6. Write the smallest failing test or fixture.
7. Run the targeted test and capture the expected failure.
8. Implement the smallest passing change.
9. Run targeted and broader relevant tests.
10. Update task state to `complete` with evidence in all task-control files.
11. Add or update follow-up tasks when needed.
12. Run `python3 scripts/validate_task_system.py`.

## Task States

Allowed task states:

```text
queued
active
blocked
implemented
verified
complete
superseded
```

State meanings:

| State | Meaning |
| --- | --- |
| `queued` | Ready but not started. |
| `active` | The single task currently being worked. |
| `blocked` | Cannot continue until a prerequisite task is inserted or a required input is obtained. |
| `implemented` | Code changes exist and targeted tests pass, but full verification has not finished. |
| `verified` | Required tests and validation passed; final status update still pending. |
| `complete` | Task is done and state files are updated. |
| `superseded` | Replaced by another task with an explicit reason. |

Only one task may be `active`, `implemented`, or `verified` pending completion at a time.

## Task-Control File Exception

The Task Queue Manager may edit `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`, and may create or rename task markdown files under `tasks/`, for lifecycle transitions, blocker insertion, queue reordering, and validator-required synchronization even when those files are not listed in the active task's allowed files.

This exception is only for task-control state. It does not allow product roles to expand implementation scope, change acceptance criteria, or hide missing prerequisite work. New prerequisite tasks use the next unused three-digit ID and an `order` key that places them before the blocked task; existing task IDs remain stable.

## Pipeline Artifact Exception

After task `041` is complete, pipeline roles may write audit artifacts under `artifacts/pipeline/<active-task-id>/**` without listing that path in each active task. The exception is task-scoped and applies only to context packets, JSON handoffs, reviews, verification reports, mutation/property/doctest evidence, and decision records defined by `docs/PIPELINE_ARTIFACTS.md`.

Agents must not use pipeline artifacts to modify product behavior, change task scope, write another task's evidence, or replace the synchronized queue/status files.

## Gap Registry Row Exception

When an active task adds, changes, or covers a documented invariant, failure mode, stable mutator, or schema contract, it may update only the matching row or newly required row in `tests/coverage-gaps/<registry>.v1.json` even when that file is not listed in the task's allowed files.

This exception is row-scoped. It does not allow broad registry cleanup, unrelated coverage claims, docs changes, schema changes, source changes, or task-scope expansion.

## Autonomous Blocker Handling

Most blockers should be resolved without user input.

Use this decision table:

| Blocker | Autonomous action |
| --- | --- |
| Missing prerequisite module | Insert a smaller prerequisite task with the next unused three-digit task ID and an `order` key before the blocked task. |
| Missing test helper | Add helper work to the current task only if allowed files permit it; otherwise insert a prerequisite task before the blocked task. |
| Spec ambiguity with conservative answer | Choose the stricter deterministic behavior and document it. |
| Spec ambiguity affecting public UX | Add a clarifying docs task and use AskUserQuestion only if two choices are equally defensible. |
| External dependency decision | Follow `docs/DEPENDENCY_POLICY.md`; do not add dependency unless policy allows it. |
| Latest stable Zig API uncertainty | Prefer public stable APIs; add adapter tests; document fallback. |
| Test failure from prior completed task | Create a regression-fix task before continuing. |

## AskUserQuestion Use

Use AskUserQuestion, or the environment's equivalent user-input tool, only for:

- irreversible product direction changes
- security tradeoffs not covered by `docs/SANDBOX_SECURITY.md`
- dependency additions forbidden or not covered by `docs/DEPENDENCY_POLICY.md`
- changing deterministic report/config/AI schema compatibility
- removing or weakening a TDD requirement

Do not ask the user for:

- routine implementation choices covered by docs
- naming that follows existing conventions
- how to fix a failing test
- whether to add a missing prerequisite task
- whether to run the validator or tests

## Role Separation

An autonomous implementation may be performed by one agent only if no multi-agent tools are available, but it must preserve these logical roles in its status entry:

| Role | Responsibility |
| --- | --- |
| Planner | Confirms task scope and referenced contracts. |
| Test Author | Writes failing tests or fixtures. |
| Test Reviewer | Checks tests would fail for the right reason and are not overfit. |
| Implementer | Writes code to pass approved tests. |
| Code Reviewer | Reviews changed code for drift, determinism, and forbidden scope expansion. |
| Verifier | Runs required commands and records evidence. |

When subagents are available and explicitly authorized by the user or environment, the Test Author and Implementer should be separate agents. Tests must not be weakened by the Implementer.

Detailed Codex role profiles live under `.agents/roles/`. Workflow runbooks live under `.agents/workflows/`.

## Follow-Up Task Rules

Follow-up tasks must be concrete. A follow-up note is insufficient.

Every new task must include:

- unique numeric ID
- title
- phase
- dependencies
- allowed files
- forbidden files
- required tests
- acceptance criteria
- execution order when different from the task ID
- machine-readable entry in `tasks/queue.json`
- Markdown task file matching the existing task template

## Completion Evidence

Each completed task must record:

- failing test evidence before implementation
- implementation summary
- files changed
- tests added
- tests run
- validator result
- dogfooding implication
- follow-up tasks created

Evidence belongs in `tasks/status.json` under `completion_evidence` and is summarized in `tasks/STATUS.md`.
