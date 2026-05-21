# 097 Autonomous Agent Contract Closure

Sequential guard: start this task only after task `096` is complete in `tasks/STATUS.md`. Task `000` is blocked until this prerequisite completes, because the latest audit found remaining autonomous-agent implementation blockers in report evidence, pipeline schema cutovers, blocker recovery, TDD enforcement wording, contract ownership, experimental backend opt-in, and doctest error evidence.

## Goal

Close the remaining repository-contract inconsistencies that could cause autonomous agents to implement zentinel from underspecified or contradictory instructions before project bootstrap begins.

## Scope

- Add validator guardrails for the remaining audit findings before fixing the contracts.
- Canonicalize generated same-file preflight evidence in report v1 docs and schema.
- Move baseline pipeline schema ownership to the task that introduces durable artifacts, leaving later tasks to validate and refine those schemas.
- Align blocker insertion docs with the direct previous-task dependency validator and provide the strict blocked-task JSON template.
- Correct TDD-first enforcement wording so it distinguishes mandatory policy from current mechanical proof limits.
- Give report-level skipped outcomes deterministic reasons, define contract-editor ownership, and clarify experimental backend CLI opt-in ownership.
- Close doctest `internal_error` evidence shape and active-task resume/validation workflow gaps.
- Preserve pinned Zig `0.16.0`, AST-default behavior, deterministic core authority, and Codex-only agent contracts.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/020-test-selection-same-file.md`
- `tasks/035-cli-doctests.md`
- `tasks/040-agent-pipeline-foundation.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/042-context-packet-system.md`
- `tasks/046-verification-pipeline.md`
- `tasks/049-pipeline-escalation.md`
- `tasks/056-zir-backend-experiment.md`
- `tasks/057-air-backend-experiment.md`
- `tasks/063-pipeline-metadata-validator.md`
- `tasks/097-autonomous-agent-contract-closure.md`
- `docs/AGENT_GUIDE.md`
- `docs/AGENT_PIPELINE_ARCHITECTURE.md`
- `docs/AGENT_ROLE_SPEC.md`
- `docs/ARCHITECTURE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/CLI_SPEC.md`
- `docs/CONFIG_SPEC.md`
- `docs/DOCTEST_SPEC.md`
- `docs/INVARIANTS.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/PIPELINE_ESCALATION_POLICY.md`
- `docs/REPORT_FORMAT.md`
- `docs/SCHEMA_REGISTRY.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/TDD_POLICY.md`
- `docs/TEST_SELECTION.md`
- `.agents/README.md`
- `.agents/ORCHESTRATOR.md`
- `.agents/roles/contract-editor.md`
- `.agents/roles/phase-planner.md`
- `.agents/roles/planner.md`
- `.agents/roles/task-queue-manager.md`
- `.agents/workflows/sync.md`
- `.agents/workflows/task-done.md`
- `.agents/workflows/task-plan.md`
- `schemas/report.v1.schema.json`
- `scripts/validate_task_system.py`
- `tests/coverage-gaps/schemas.v1.json`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `.claude/**`

## Required tests

- First add a failing structural validator guardrail for the audit findings listed in scope.
- Run `python3 scripts/validate_task_system.py` after adding the guardrails and record the expected failures before fixing contracts.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for edited JSON and schema files.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` while task `097` is still active.
- Run `python3 scripts/validate_task_system.py` again after marking task `097` complete.

## Acceptance criteria

- Report v1 has a canonical `selection_preflight`/preflight evidence location for generated selected commands, and test-selection docs point to it.
- Task `041` owns baseline pipeline handoff, active-lock, context, stale-context, verification, and escalation schema creation; task `063` owns validator implementation and refinement without relying on missing schemas.
- Prerequisite insertion docs require the inserted task to depend on the immediately previous non-superseded execution-order task.
- Blocked-task docs include a machine-readable JSON template matching `tasks/status.json` and `tasks/schema/status.v1.schema.json`.
- `tasks/STATUS.md`, `docs/TDD_POLICY.md`, and invariant wording distinguish required TDD-first discipline from currently limited mechanical chronology proof.
- Skipped mutant report entries carry a deterministic result-level skip reason, not only command-level skip reasons.
- Architecture/public-contract edits have a named Contract Editor role and routing path.
- ZIR/AIR backend opt-in CLI ownership is explicit and task-scoped.
- Doctest `internal_error` reports have a closed `run.error` shape.
- Active-task resume and immediate post-activation validation are explicit in agent workflows, and Markdown queue row order must match queue JSON order.
- `tasks/STATUS.md` records completion, files changed, tests run, and no prose-only follow-up.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Project bootstrap source creation.
- Runtime mutation behavior.
- New Zig tests or source modules.
- Implementing report writers, doctest runners, backend experiments, or pipeline artifact tooling.

## Suggested implementation approach

1. Add validator checks first so the current drift fails.
2. Align docs, schemas, affected future task files, and validator behavior.
3. Keep report schema changes additive within the existing v1 contract.
4. Complete the task only after active-scope validation and final complete-state validation pass.

## Dogfooding implications

This task removes autonomous-agent blockers before any dogfoodable zentinel runtime exists. No zentinel dogfood run is expected.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
