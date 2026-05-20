# 079 Status Completion Evidence Schema

Sequential guard: start this task only after task 078 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Make task completion evidence machine-checkable in `tasks/status.json` before pipeline artifacts exist.

## Scope

- Add structured completion evidence to the task status schema.
- Populate `tasks/status.json` evidence for completed pre-bootstrap tasks.
- Update protocol wording to name the structured status field.
- Add validator checks requiring completion evidence for every completed task.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/079-status-completion-evidence-schema.md`
- `tasks/000-project-bootstrap.md`
- `tasks/schema/status.v1.schema.json`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/AGENT_GUIDE.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `docs/DOCTEST_*.md`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail that rejects completed tasks without structured `completion_evidence` in `tasks/status.json`.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating status JSON and schema.
- Run `python3 scripts/validate_task_system.py` after structured evidence is populated.

## Acceptance criteria

- `tasks/schema/status.v1.schema.json` defines `completion_evidence`.
- `tasks/status.json` contains one structured completion evidence entry for every completed task.
- The validator rejects completed tasks without evidence.
- Pre-artifact status evidence includes failing evidence, implementation summary, files changed, tests added, tests run, validator result, dogfooding implication, and follow-up tasks.
- No product implementation files are changed.

## Non-goals

- Adding pipeline artifacts before task 041.
- Replacing the Markdown completion log.
- Changing historical task scope.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on the missing structured evidence.
2. Extend the status schema and protocol text.
3. Populate concise evidence entries from the existing Markdown completion log and task history.
4. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task makes pre-artifact task evidence durable enough for fresh agents before dogfood and pipeline artifact tasks exist.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
