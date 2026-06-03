# zentinel Agent Instructions

This repository is designed for autonomous sequential AI-agent implementation. Agents must be able to build zentinel end to end without human planning between tasks.

## Required Reading

Before changing files, read:

1. `tasks/QUEUE.md`
2. `tasks/queue.json`
3. `tasks/STATUS.md`
4. `tasks/status.json`
5. `docs/VISION.md`
6. `docs/NON_GOALS.md`
7. `docs/GLOSSARY.md`
8. `docs/AGENT_GUIDE.md`
9. `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
10. `.agents/README.md`
11. `.agents/ORCHESTRATOR.md`
12. the active task file

For behavior changes, also read:

- `docs/TDD_POLICY.md`
- `docs/ARCHITECTURE.md`
- `docs/INVARIANTS.md`
- `docs/DISCIPLINE.md`
- `docs/STYLE.md`
- the relevant spec document under `docs/`

## Non-Negotiable Rules

- Execute tasks sequentially.
- Keep exactly one task active.
- Write failing tests before implementation.
- Modify only files allowed by the active task, except task-control state updates performed by the Task Queue Manager, row-scoped gap registry updates under `tests/coverage-gaps/<registry>.v1.json`, and task-scoped pipeline artifacts after task `041` is complete.
- Preserve deterministic core behavior.
- Support only pinned Zig `0.16.0` for this zentinel version.
- Keep AST as the stable default backend.
- Treat ZIR as experimental only.
- Never use AI output to determine mutation correctness.
- Dogfood zentinel as soon as the task system requires it.
- Cite `docs/INVARIANTS.md`, `docs/DISCIPLINE.md`, `docs/STYLE.md`, or ADR IDs when they govern a non-obvious choice.
- Develop zentinel with provider-neutral agent contracts under `.agents/`; any MCP-capable agent runtime (for example Codex or Claude) may drive development by following them. Do not commit provider-specific files such as `.claude/` or other runtime command/profile/settings files to the repository.

## Machine-Checkable Workflow

Agents must keep Markdown and JSON task state synchronized:

- `tasks/QUEUE.md` and `tasks/queue.json`
- `tasks/STATUS.md` and `tasks/status.json`
- docs-to-tests gap registries under `tests/coverage-gaps/` when changing covered docs contracts

The task-control files are a narrow scope exception. The Task Queue Manager may edit `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`, and may create or rename task markdown files under `tasks/`, only for lifecycle transitions, blocker insertion, queue reordering, or validator-required synchronization. Product implementation roles must not use this exception to change task scope opportunistically.

Gap registry files are a narrow row-scoped exception. When the active task adds, changes, or covers a documented invariant, failure mode, stable mutator, or schema contract, the task may update only the matching row or newly required row in `tests/coverage-gaps/<registry>.v1.json` even when that registry file is not listed in the active task's allowed files. This exception does not authorize unrelated registry cleanup, source changes, docs changes, schema changes, or task-scope expansion.

After task `041` is complete, pipeline roles may create or update only their active task's audit artifacts under `artifacts/pipeline/<active-task-id>/**` even when that path is not listed in the active task's allowed files. This exception is limited to handoffs, reviews, verification evidence, context packets, and other pipeline metadata defined by `docs/PIPELINE_ARTIFACTS.md`; it does not permit product source, docs, tests, schemas, or task-scope changes outside the active task.

Run this before completing any task:

```bash
python3 scripts/validate_task_system.py
```

If the validator fails, fix the task metadata or status files before proceeding.

## Autonomous Blocker Resolution

If a task is blocked:

1. Do not ask the user unless the choice is irreversible or explicitly requires product judgment.
2. Add the smallest prerequisite task to the queue using the next unused three-digit task ID and an execution `order` before the blocked task.
3. Update `tasks/queue.json`, `tasks/QUEUE.md`, `tasks/status.json`, and `tasks/STATUS.md`.
4. Run `python3 scripts/validate_task_system.py`.
5. Execute the prerequisite task, then resume.

Use the AskUserQuestion tool, or the environment's equivalent user-input tool, only when the repository contracts do not provide enough information to choose safely.

## Completion Standard

A task is complete only when:

- required tests were added before implementation
- targeted tests pass
- broader relevant tests pass
- task status is updated in Markdown and JSON
- validator passes
- no forbidden files were modified, except Task Queue Manager edits to task-control files, row-scoped gap registry updates under `tests/coverage-gaps/<registry>.v1.json`, and task-scoped pipeline artifacts allowed after task `041`
- follow-up work is captured as tasks, not prose-only notes
