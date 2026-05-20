# 071 Agent Contract Finalization

Sequential guard: start this task only after task 070 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Resolve the remaining pre-bootstrap agent implementation blockers from the deep repository analysis.

## Scope

- Align Codex orchestrator role routing with `docs/PIPELINE_ESCALATION_POLICY.md`.
- Clarify task `063` pipeline metadata validator ownership for baseline schema files versus later schema refinements.
- Add generated Zig artifact ignore rules before `zig build test` can create `.zig-cache/` or `zig-out/`.
- Remove stale task-status history that says the tracked baseline is still untracked.
- Add structural validator guardrails so these contracts do not regress.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/071-agent-contract-finalization.md`
- `tasks/000-project-bootstrap.md`
- `tasks/042-context-packet-system.md`
- `tasks/046-verification-pipeline.md`
- `tasks/049-pipeline-escalation.md`
- `tasks/063-pipeline-metadata-validator.md`
- `.agents/ORCHESTRATOR.md`
- `docs/PIPELINE_ESCALATION_POLICY.md`
- `docs/SCHEMA_REGISTRY.md`
- `tests/coverage-gaps/schemas.v1.json`
- `scripts/validate_task_system.py`
- `.gitignore`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `docs/MUTATOR_SPEC.md`
- `.claude/**`

## Required tests

- Add a failing validator guardrail proving `.agents/ORCHESTRATOR.md` complexity routing mirrors `docs/PIPELINE_ESCALATION_POLICY.md`.
- Add a failing validator guardrail proving pipeline schema ownership distinguishes task `063` baseline schema validation from later task-specific schema refinements.
- Add a failing validator guardrail proving `.gitignore` protects Zig build outputs.
- Add a failing validator guardrail rejecting stale untracked-baseline status history.
- Run `python3 scripts/validate_task_system.py` and record the failure before contract fixes.

## Acceptance criteria

- `.agents/ORCHESTRATOR.md` and `docs/PIPELINE_ESCALATION_POLICY.md` no longer specify different minimum roles for the same complexity class.
- Task `063` is explicitly responsible for baseline pipeline schema files needed by the metadata validator, while tasks `042`, `046`, and `049` retain ownership of later semantic refinements.
- `.gitignore` ignores `.zig-cache/` and `zig-out/`.
- Task status no longer claims the tracked baseline is untracked.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Runtime orchestration.
- Zig project bootstrap implementation.
- Pipeline artifact persistence.
- Product mutation behavior.

## Suggested implementation approach

1. Add validator guardrails first and confirm they fail on the current contracts.
2. Update the orchestrator routing table to mirror the escalation policy.
3. Clarify pipeline schema ownership in task metadata, schema registry notes, and coverage-gap rows.
4. Add ignore rules for Zig-generated build artifacts.
5. Update task status and run validation.

## Dogfooding implications

This task removes contract drift before zentinel can dogfood itself. No dogfood run is expected yet.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
