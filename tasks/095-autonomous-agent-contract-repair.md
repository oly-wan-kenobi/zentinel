# 095 Autonomous Agent Contract Repair

Sequential guard: start this task only after task `094` is complete in `tasks/STATUS.md`. Task `000` is blocked until this prerequisite completes, because autonomous agents need consistent lifecycle, validator, schema, and task-scope contracts before project bootstrap begins.

## Goal

Repair the remaining autonomous-agent implementation blockers found by the four-lane deep analysis before any Zig scaffold or runtime behavior is created.

## Scope

- Align task-control lifecycle wording so `implemented` and `verified` are pipeline artifact stages only, not normal queue/status states.
- Strengthen validator guardrails for final dirty-file scope, task-control states, AI context command evidence, pipeline artifact cutovers, gap registry evidence, and task scopes discovered to be too narrow.
- Align AI context and report schemas with their docs for command `failure_kind` and baseline compiler-crash evidence.
- Widen only the affected future task scopes so agents can satisfy TDD without violating allowed-file discipline.
- Preserve pinned Zig `0.16.0`, AST-default behavior, and Codex-only agent contracts.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/014-baseline-runner.md`
- `tasks/020-test-selection-same-file.md`
- `tasks/040-agent-pipeline-foundation.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/046-verification-pipeline.md`
- `tasks/051-fail-fast-impact-analysis.md`
- `tasks/063-pipeline-metadata-validator.md`
- `tasks/095-autonomous-agent-contract-repair.md`
- `tasks/schema/queue.v1.schema.json`
- `tasks/schema/status.v1.schema.json`
- `.agents/README.md`
- `.agents/ORCHESTRATOR.md`
- `.agents/roles/task-queue-manager.md`
- `.agents/workflows/sync.md`
- `.agents/workflows/task-done.md`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/AGENT_PIPELINE_ARCHITECTURE.md`
- `docs/AGENT_ROLE_SPEC.md`
- `docs/SEQUENTIAL_EXECUTION_POLICY.md`
- `docs/GAP_REGISTRIES.md`
- `docs/CONFIG_SPEC.md`
- `docs/REPORT_FORMAT.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/SCHEMA_REGISTRY.md`
- `docs/INTERNAL_API_CONTRACTS.md`
- `docs/INVARIANTS.md`
- `schemas/ai.context.v1.schema.json`
- `schemas/report.v1.schema.json`
- `scripts/validate_task_system.py`
- `tests/coverage-gaps/invariants.v1.json`
- `tests/coverage-gaps/schemas.v1.json`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `.claude/**`

## Required tests

- First add a failing structural validator guardrail for the stale lifecycle, final dirty-file scope, AI context `failure_kind`, baseline compiler-crash schema, pre-`041` artifact cutover, row-scoped gap registry evidence, and future task-scope blockers.
- Run `python3 scripts/validate_task_system.py` after adding the guardrails and record the expected failures before fixing contracts.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for edited JSON files.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` while task `095` is still active.
- Run `python3 scripts/validate_task_system.py` again after marking task `095` complete.

## Acceptance criteria

- `.agents/` and `docs/` agree that task-control states are `queued`, `active`, `blocked`, `complete`, and `superseded`; `implemented` and `verified` appear only as artifact stages.
- The validator rejects `implemented` and `verified` in `tasks/queue.json` for normal work and rejects stale agent lifecycle wording.
- Final validation after completion checks actual dirty files against the latest completion evidence instead of trusting evidence alone.
- `schemas/ai.context.v1.schema.json` accepts and requires command `failure_kind` where `docs/AI_CONTEXT_SCHEMA.md` requires it.
- Baseline command results have deterministic compiler-crash semantics in docs, task requirements, and `schemas/report.v1.schema.json`.
- Tasks `020` and `051` own enough config surface to reject and later accept `impact_graph` under TDD.
- Task `040` can prove I-019 without violating file scope, and task `041` explicitly allows external schema/fixture validation until task `063` owns project validation tooling.
- Gap registry rows list existing test paths or explicitly remain uncovered/deferred; row-scoped registry evidence no longer relies only on self-reporting.
- `tasks/STATUS.md` records completion, files changed, tests run, and no prose-only follow-up.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Project bootstrap source creation.
- Runtime mutation behavior.
- New Zig tests or source modules.
- Implementing AI providers, doctests, cache, runner execution, or pipeline artifact tooling.

## Suggested implementation approach

1. Add validator checks first so the current stale contracts fail.
2. Align docs, schemas, and affected task files in small commits.
3. Keep schema changes additive within the existing v1 contracts unless the task requires a validator-only task-system tightening.
4. Complete the task only after active-scope validation and final complete-state validation pass.

## Dogfooding implications

This task removes autonomous-agent blockers before any dogfoodable zentinel runtime exists. No zentinel dogfood run is expected.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
