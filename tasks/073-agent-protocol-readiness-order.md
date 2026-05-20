# 073 Agent Protocol Readiness Order

Sequential guard: start this task only after task 072 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Align autonomous task-start instructions so agents read the selected task and required docs before marking it active or editing implementation files.

## Scope

- Clarify the Standard Agent Loop ordering.
- Align task queue and agent guide lifecycle wording with the safer read-before-activate flow.
- Add a structural validator guardrail for this ordering contract.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/073-agent-protocol-readiness-order.md`
- `tasks/000-project-bootstrap.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/AGENT_GUIDE.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail that rejects mark-active-before-read startup wording.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating the affected docs.
- Run `python3 scripts/validate_task_system.py` after the docs and task metadata are aligned.

## Acceptance criteria

- The Standard Agent Loop reads the selected task file and required docs before marking a task active.
- `tasks/QUEUE.md` and `docs/AGENT_GUIDE.md` no longer instruct agents to mark active before reading the selected task file.
- The validator preserves the ordering contract.
- No implementation files are changed.

## Non-goals

- Changing product behavior.
- Changing task lifecycle states.
- Adding pipeline artifacts before task 041.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on the existing stale wording.
2. Update the protocol, queue, and guide wording to the read-before-activate order.
3. Keep the change limited to lifecycle ordering language.
4. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task reduces pre-bootstrap agent startup ambiguity before dogfoodable behavior is implemented.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
