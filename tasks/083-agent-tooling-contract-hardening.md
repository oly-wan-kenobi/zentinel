# 083 Agent Tooling Contract Hardening

Sequential guard: start this task only after task `082` is complete and `tasks/status.json` names `083` as the next queued task. No later-order task may begin until this task is complete.

## Goal

Remove residual pre-bootstrap agent tooling hazards around execution order, task references, report validation authority, and latest-stable Zig verification.

## Scope

- Make queue execution order explicit in every machine-readable task entry.
- Canonicalize follow-up task references so task markdown always uses `tasks/<id>-<name>.md`.
- Clarify that report JSON Schema validation is supplemented by deterministic semantic validation for derived invariants.
- Require task `005` to capture durable evidence for official latest-stable Zig release verification.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/083-agent-tooling-contract-hardening.md`
- `tasks/000-project-bootstrap.md`
- `tasks/005-version-policy.md`
- `tasks/006-report-schema.md`
- `tasks/040-agent-pipeline-foundation.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/042-context-packet-system.md`
- `tasks/043-mutation-gate.md`
- `tasks/044-property-test-policy.md`
- `tasks/045-doctest-policy.md`
- `tasks/046-verification-pipeline.md`
- `tasks/047-sequential-task-locking.md`
- `tasks/048-failure-recovery.md`
- `tasks/schema/queue.v1.schema.json`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/REPORT_FORMAT.md`
- `docs/SEQUENTIAL_EXECUTION_POLICY.md`
- `docs/ZIG_VERSION_POLICY.md`
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

- Add a failing validator guardrail requiring every `tasks/queue.json` task entry to contain an explicit `order` field and requiring the queue schema to list `order` as required.
- Add a failing validator guardrail rejecting bare follow-up task refs such as `` `041-handoff-artifacts.md` ``.
- Add failing validator coverage requiring report semantic validation wording in `docs/REPORT_FORMAT.md` and task `006`.
- Add failing validator coverage requiring task `005` to capture official release source, official latest stable version, local `zig version`, and match or mismatch evidence.
- Run `python3 scripts/validate_task_system.py`.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for task-control files and schemas.
- Run `git diff --check`.

## Acceptance criteria

- Every `tasks/queue.json` task has an explicit `order`, and `tasks/schema/queue.v1.schema.json` requires it.
- Follow-up task refs in task markdown use canonical `tasks/<id>-<name>.md` paths and the validator rejects bare refs.
- Report contracts state that deterministic semantic validation must check derived invariants in addition to JSON Schema shape validation.
- Task `005` requires durable latest-stable Zig verification evidence and keeps the policy version-agnostic.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing Zig source, build files, or tests.
- Implementing the report semantic validator.
- Performing task `005`'s live Zig release verification during this pre-bootstrap cleanup.
- Changing report schema semantics.

## Suggested implementation approach

1. Add the validator checks first and record the expected failures.
2. Apply the smallest metadata, docs, schema, and task-file changes needed for the checks to pass.
3. Keep all queue and status files synchronized.
4. Re-run validator, Python compilation, JSON syntax checks, and whitespace checks.

## Dogfooding implications

No dogfood run exists yet. This task prevents simple autonomous tools from misreading queue order or accepting logically inconsistent future report artifacts.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
