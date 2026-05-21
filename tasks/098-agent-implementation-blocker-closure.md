# 098 Agent Implementation Blocker Closure

Sequential guard: start this task only after task `097` is complete in `tasks/STATUS.md`. Task `000` is blocked until this prerequisite completes, because the latest four-subagent implementation analysis found remaining blockers in task-boundary handoff semantics, I-019 chronology ownership, pipeline artifact cutovers, AI context result evidence, command phase labels, pre-041 handoff paths, Contract Editor ordering, and final dogfood artifact paths.

## Goal

Close the remaining inconsistencies that could block autonomous AI agents from implementing zentinel sequentially after project bootstrap starts.

## Scope

- Add validator guardrails for the approved implementation-blocker findings before fixing the contracts.
- Define a clean handoff boundary so future task activation is not blocked by prior-task dirty files or hidden committed scope drift.
- Correct I-019 coverage ownership so task `040` preserves TDD wording but does not claim mechanical chronology coverage before artifact timestamp validation exists.
- Align task `041` and task `063` around all baseline pipeline schema fixtures, active-lock/context creation order, and immediate post-`041` validator consumption.
- Add result-level `skip_reason` to AI context v1 so AI advisory payloads preserve the canonical report evidence shape.
- Include `selection_preflight` wherever command phase labels are enumerated for reports and sandbox evidence.
- Define pre-`041` handoff location and fields precisely enough for stateless agents before durable pipeline artifacts exist.
- Clarify Contract Editor ordering relative to Test Author and public contract changes.
- Define the canonical final dogfood archive path under task-scoped pipeline artifacts while keeping `zig-out` runtime-only.
- Preserve pinned Zig `0.16.0`, AST-default behavior, deterministic core authority, and Codex-only agent contracts.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/040-agent-pipeline-foundation.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/053-ai-provider-and-context.md`
- `tasks/063-pipeline-metadata-validator.md`
- `tasks/085-final-dogfood-release-gate.md`
- `tasks/098-agent-implementation-blocker-closure.md`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/AGENT_PIPELINE_ARCHITECTURE.md`
- `docs/AGENT_CONTEXT_PACKETS.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/HANDOFF_CONTRACTS.md`
- `docs/TDD_POLICY.md`
- `docs/INVARIANTS.md`
- `docs/GAP_REGISTRIES.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/REPORT_FORMAT.md`
- `docs/SANDBOX_SECURITY.md`
- `docs/TEST_SELECTION.md`
- `docs/CI_STRATEGY.md`
- `docs/DOGFOODING.md`
- `docs/PROJECT_ACCEPTANCE_CRITERIA.md`
- `docs/SEQUENTIAL_EXECUTION_POLICY.md`
- `.agents/README.md`
- `.agents/ORCHESTRATOR.md`
- `.agents/roles/contract-editor.md`
- `.agents/workflows/task-plan.md`
- `.agents/workflows/task-done.md`
- `schemas/ai.context.v1.schema.json`
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

- First add a failing structural validator guardrail for the implementation-blocker findings listed in scope.
- Run `python3 scripts/validate_task_system.py` after adding the guardrails and record the expected failures before fixing contracts.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for edited JSON and schema files.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` while task `098` is still active.
- Run `python3 scripts/validate_task_system.py` again after marking task `098` complete.

## Acceptance criteria

- Agent workflow docs define a clean handoff boundary before activating a different task, including the exact commit or recorded baseline expectation for prior task changes.
- I-019 remains mandatory but its gap registry row no longer claims coverage through task `040`; mechanical chronology proof is deferred to the pipeline metadata validator cutover.
- Task `041` owns fixtures for all baseline pipeline schema files it creates, and task `063` is allowed to read and validate all baseline pipeline schemas without creating them.
- Post-`041` active-task startup order is explicit: mark task active, create active lock and context packet, then run validation before role work starts.
- AI context v1 includes result-level `skip_reason` aligned with report v1, and task `053` owns deterministic schema/context coverage for it.
- Sandbox and command evidence docs include `selection_preflight` alongside `baseline` and `mutant`.
- Pre-`041` handoffs have a canonical task-status location and required fields rather than relying on chat history.
- Contract Editor runs before Test Author when the task changes public contracts that tests depend on; otherwise tests remain first.
- Final dogfood release evidence uses canonical archived paths under `artifacts/pipeline/<task-id>/dogfood/`, while `zig-out` remains a runtime output path.
- `tasks/STATUS.md` records completion, files changed, tests run, and no prose-only follow-up.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Project bootstrap source creation.
- Runtime mutation behavior.
- New Zig tests or source modules.
- Implementing pipeline artifact writers, AI commands, dogfood execution, or schema validation beyond structural guardrails.

## Suggested implementation approach

1. Activate this prerequisite and run the existing validator.
2. Add validator checks first so the current drift fails.
3. Align docs, schema, gap rows, affected future task files, and validator guardrails.
4. Complete the task only after active-scope validation and final complete-state validation pass.

## Dogfooding implications

This task removes autonomous-agent blockers before any dogfoodable zentinel runtime exists. No zentinel dogfood run is expected.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
