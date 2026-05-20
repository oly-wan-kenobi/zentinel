# 084 Agent Contract Cutover Closure

Sequential guard: start this task only after task `083` is complete and `tasks/status.json` names `084` as the next queued task. No later-order task may begin until this task is complete.

## Goal

Resolve the remaining pre-bootstrap agent-contract cutover ambiguities before project implementation starts.

## Scope

- Clarify `docs/TASK_LIFECYCLE.md` so pre-041 tasks use synchronized task-control files as the active-task lock and do not require durable pipeline artifacts before those artifacts exist.
- Clarify completion gates in `docs/TASK_LIFECYCLE.md` so review, verifier, property, doctest, mutation, and artifact gates apply only when the relevant task or cutover has introduced them.
- Clarify `docs/PROPERTY_TEST_POLICY.md` so deterministic property-style tests are acceptable before generated property-test infrastructure exists, while preserving mandatory generated property evidence after the infrastructure cutover.
- Align pre-artifact handoff wording in `.agents/README.md` and `docs/AGENT_GUIDE.md` with the machine-checkable `tasks/status.json` completion-evidence subset.
- Add validator guardrails for these cutover contracts.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/084-agent-contract-cutover-closure.md`
- `tasks/000-project-bootstrap.md`
- `.agents/README.md`
- `docs/AGENT_GUIDE.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/PROPERTY_TEST_POLICY.md`
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

- Add a failing validator guardrail that rejects lifecycle docs without the pre-041 active-lock and artifact cutovers.
- Add a failing validator guardrail that rejects property-test policy wording without the pre-044/pre-062 staged evidence rule.
- Add a failing validator guardrail that rejects pre-artifact handoff docs implying that `tasks/status.json` must carry fields outside its completion-evidence subset.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating the docs.
- Run `python3 scripts/validate_task_system.py` after the contracts are aligned.

## Acceptance criteria

- Task lifecycle docs no longer require active-lock artifacts, verifier reports, or durable handoff artifacts before task `041` introduces them.
- Mutation-gate completion wording does not block pre-043 tasks on nonexistent mutation tooling.
- Property-test policy distinguishes property-style deterministic evidence before task `062` from generated property-test infrastructure after task `062`.
- Pre-artifact handoff docs clearly separate full human-readable handoff fields from the narrower machine-checkable `completion_evidence` subset in `tasks/status.json`.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing runtime zentinel behavior.
- Creating pipeline artifact writers.
- Moving task `041`, task `043`, task `044`, or task `062`.
- Changing product mutation semantics.

## Suggested implementation approach

1. Insert this prerequisite before task `000` and mark it active.
2. Add validator phrase checks for the three contract fixes first.
3. Run the validator and capture the expected failure.
4. Update only the scoped docs and task metadata.
5. Run validation and record completion evidence.

## Dogfooding implications

No dogfood run exists yet. This task prevents pre-bootstrap agents from blocking on nonexistent pipeline, property, or mutation infrastructure while preserving those gates once their cutover tasks complete.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
