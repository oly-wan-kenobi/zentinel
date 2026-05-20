# 086 Validator Scope and Report Semantic Clarity

Sequential guard: start this task only after task `084` is complete and `tasks/status.json` names `086` as the next queued task. No later-order task may begin until this task is complete.

## Goal

Clarify that the task-system validator is not a product semantic oracle and strengthen the report-schema task so it owns deterministic semantic report validation.

## Scope

- State in agent-facing docs and status handoff text that `scripts/validate_task_system.py` validates task-system consistency, not product semantic correctness.
- Strengthen task `006` so report semantic validation covers derived invariants beyond JSON Schema shape.
- Add validator guardrails for the new wording.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/086-validator-scope-and-report-semantic-clarity.md`
- `tasks/000-project-bootstrap.md`
- `tasks/006-report-schema.md`
- `docs/AGENT_GUIDE.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `docs/MUTATOR_SPEC.md`
- `.claude/**`

## Required tests

- Add a failing validator guardrail requiring agent-facing docs and status handoff text to say the validator checks task-system consistency, not product semantic correctness.
- Add a failing validator guardrail requiring task `006` to own a deterministic report semantic validator for derived invariants beyond schema shape.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating docs and task wording.
- Run `python3 scripts/validate_task_system.py` after the contracts are aligned.

## Acceptance criteria

- `docs/AGENT_GUIDE.md` warns agents not to treat task-system validation as product semantic proof.
- `tasks/STATUS.md` carries the same warning for fresh handoffs.
- Task `006` requires semantic validation of derived report invariants in addition to JSON Schema validation.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing report serialization.
- Changing report schema fields.
- Changing runtime zentinel behavior.

## Suggested implementation approach

1. Add validator phrase checks first and confirm the validator fails on the current wording.
2. Update the guide, status handoff, and task `006` text only as needed.
3. Complete the task and leave project bootstrap as the next dependency-ready task.

## Dogfooding implications

No runtime behavior exists yet. This task prevents agents from treating governance validation as a substitute for deterministic product tests once dogfoodable behavior exists.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
