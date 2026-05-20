# 092 Agent Readiness Follow-up Hardening

Sequential guard: start this task only after task `091` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Close the latest read-only analysis findings before project bootstrap so autonomous agents can continue without hidden contract gaps.

## Scope

- Add structural validator guardrails for the identified task, handoff, backend, and task-state drift.
- Clarify task `030` doctest fixture validation evidence.
- Clarify post-`041` handoff naming and test-evidence semantics for every pipeline role.
- Align `Code Reviewer` wording with the canonical `Implementation Reviewer` role.
- Align experimental backend diagnostics with the closed report v1 schema.
- Replace stale latest-stable backend wording with the pinned Zig `0.16.0` contract.
- Harden task queue/status validation around schema-shaped fields, Markdown queue rows, completed-task sync, blocked-state details, and active-task changed-file scope.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/092-agent-readiness-follow-up-hardening.md`
- `tasks/000-project-bootstrap.md`
- `tasks/030-doctest-conventions.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/056-zir-backend-experiment.md`
- `tasks/057-air-backend-experiment.md`
- `tasks/schema/status.v1.schema.json`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/HANDOFF_CONTRACTS.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `.agents/README.md`
- `docs/AST_BACKEND.md`
- `docs/ZIR_BACKEND.md`
- `docs/AIR_BACKEND.md`
- `docs/REPORT_FORMAT.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/report.v1.schema.json`
- `docs/MUTATOR_SPEC.md`
- `.claude/**`

## Required tests

- Add failing validator guardrails for task `030` doctest fixture evidence, post-`041` handoff role coverage, canonical `Implementation Reviewer` wording, experimental backend report-schema alignment, pinned Zig backend wording, task-state schema shape, completed-task sync, extra Markdown queue rows, blocked-state details, and active-task changed-file scope.
- Run `python3 scripts/validate_task_system.py` after adding the guardrails and record the expected failure before contract updates.
- Run `python3 scripts/validate_task_system.py` after implementation.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for edited JSON files.
- Run `git diff --check`.

## Acceptance criteria

- Task `030` has executable validator-backed fixture-presence evidence without requiring scripts edits during task `030`.
- Post-`041` handoff contracts define deterministic names and required content for every pipeline role that can emit a handoff.
- Handoff `tests_added` semantics are unambiguous for non-test-author roles.
- Agent role wording uses canonical `Implementation Reviewer` terminology.
- ZIR and AIR diagnostics do not require schema-invalid report v1 fields.
- Backend docs consistently cite pinned Zig `0.16.0`, not latest-stable lookup.
- Task queue/status validation rejects schema-shape drift, stale completed-task status, extra Markdown queue rows, missing blocked-state detail, and active-task diffs outside allowed scope.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing product runtime behavior.
- Changing report v1 schema shape.
- Adding pipeline artifact runtime writers.
- Implementing doctest execution.

## Suggested implementation approach

1. Add validator guardrails first and confirm they fail on the current contracts.
2. Update docs and task files to satisfy the guardrails.
3. Keep report v1 closed by making experimental backend diagnostics out-of-report artifacts until a future schema task changes that.
4. Update task status and completion evidence after validation passes.

## Dogfooding implications

This task removes autonomous-agent blockers before dogfoodable product code exists. No zentinel dogfood run is expected yet.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
