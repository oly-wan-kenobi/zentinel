# 075 Mutation Gate Availability Policy

Sequential guard: start this task only after task 074 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Clarify that mutation-gate requirements become mandatory only after task 043 defines the gate and once the active scope is mutation-testable.

## Scope

- Refine `docs/MUTATION_GATE_POLICY.md` so pre-gate tasks can record a deterministic skip reason instead of being blocked by a nonexistent gate.
- Align task 043 wording with the policy cutover.
- Add a structural validator guardrail for the mutation-gate availability contract.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/075-mutation-gate-availability-policy.md`
- `tasks/000-project-bootstrap.md`
- `tasks/043-mutation-gate.md`
- `docs/MUTATION_GATE_POLICY.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail that rejects mutation-gate policy wording without the task 043 cutover and pre-gate skip reason.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating the policy text.
- Run `python3 scripts/validate_task_system.py` after the policy and task metadata are aligned.

## Acceptance criteria

- The mutation gate remains mandatory for mutation-testable work after task 043 is complete.
- Tasks before task 043 may record a `pre-gate unavailable` skip reason when the gate cannot exist yet.
- Task 043 still defines the mutation gate and does not claim to run product mutation checks before runtime support exists.
- The validator preserves the availability cutover wording.
- No product implementation files are changed.

## Non-goals

- Moving task 043.
- Implementing mutation-gate runtime behavior.
- Weakening future dogfood or mutation-testable task gates.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on the current policy.
2. Update the policy with an explicit task 043 cutover and pre-gate skip reason.
3. Align task 043 acceptance and dogfooding wording.
4. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task prevents pre-gate tasks from blocking on nonexistent tooling while preserving mandatory mutation gates once dogfoodable mutation behavior exists.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
