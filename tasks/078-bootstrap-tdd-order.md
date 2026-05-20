# 078 Bootstrap TDD Order

Sequential guard: start this task only after task 077 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Remove ambiguity in task 000 by aligning its suggested implementation approach with the required failing-test-first bootstrap workflow.

## Scope

- Clarify that task 000 starts by adding failing bootstrap tests before the build scaffold.
- Document acceptable pre-scaffold failing evidence for `zig build test`.
- Add a structural validator guardrail for the bootstrap TDD order.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/078-bootstrap-tdd-order.md`
- `tasks/000-project-bootstrap.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `docs/**`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail that rejects task 000 if its suggested approach starts with `build.zig` before failing tests.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating task 000.
- Run `python3 scripts/validate_task_system.py` after task 000 is aligned.

## Acceptance criteria

- Task 000 tells agents to add `test/bootstrap_test.zig` and `test/bootstrap_discovery_test.zig` before adding `build.zig`.
- Task 000 explicitly allows the first failure to be the missing build scaffold or unresolved root-module import.
- The validator preserves this bootstrap TDD ordering.
- No product implementation files are changed.

## Non-goals

- Implementing the Zig project scaffold.
- Changing bootstrap allowed files beyond dependency guard metadata.
- Weakening the TDD-first requirement.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on task 000's current suggested approach.
2. Update only task 000 wording needed to align required tests and suggested implementation order.
3. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task keeps the first implementation task from training agents to build before writing failing evidence.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
