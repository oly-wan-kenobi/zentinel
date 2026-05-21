# 099 Handoff Baseline and Contract Drift Closure

Sequential guard: start only after task `098` is complete. Task `000` remains blocked until this prerequisite task records a machine-readable clean handoff baseline and closes the downstream contract drifts that would otherwise block autonomous AI-agent implementation.

## Goal

Make the post-`098` handoff baseline validator-readable, make scope checks compare against that baseline rather than only `HEAD`, and close the underspecified downstream contracts identified by the implementation-readiness analysis.

## Scope

- Add failing structural validator guardrails before implementation for:
  - the clean handoff baseline schema and validator behavior
  - post-`041` startup ordering between pipeline artifacts and validation
  - AI prompt skip evidence shape
  - report invalid-classifier evidence
  - task `001` version output expectations
  - semantic mutator filter-vs-`compile_error` classification
  - ZIR/AIR diagnostic artifact paths
  - mutation-aware doctest runner failure evidence
- Add a machine-readable `clean_handoff_baseline` contract to task status metadata.
- Make active and inactive changed-file scope validation ignore only unchanged files explicitly covered by the current clean handoff baseline.
- Preserve detection of new unbaselined dirty files, deleted baselined files, and baselined files whose content no longer matches the recorded hash.
- Update agent-facing docs and workflows so pre-`041` and post-`041` validation startup order is unambiguous.
- Close the downstream docs/task/spec drifts without changing zentinel product behavior.
- Keep Zig `0.16.0`, AST as the stable default backend, ZIR/AIR experimental status, deterministic core behavior, and Codex-only agent contracts unchanged.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/001-cli-shell.md`
- `tasks/006-report-schema.md`
- `tasks/023-optional-null-mutators.md`
- `tasks/024-error-path-mutators.md`
- `tasks/026-errdefer-mutator.md`
- `tasks/027-integer-literal-boundary-mutator.md`
- `tasks/028-loop-boundary-mutator.md`
- `tasks/039-doctest-mutation-experiments.md`
- `tasks/040-agent-pipeline-foundation.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/053-ai-provider-and-context.md`
- `tasks/054-ai-advisory-commands.md`
- `tasks/056-zir-backend-experiment.md`
- `tasks/057-air-backend-experiment.md`
- `tasks/061-doctest-mutate-stabilization.md`
- `tasks/063-pipeline-metadata-validator.md`
- `tasks/067-ai-doctest-survivor-assistance.md`
- `tasks/085-final-dogfood-release-gate.md`
- `tasks/098-agent-implementation-blocker-closure.md`
- `tasks/099-handoff-baseline-and-contract-drift-closure.md`
- `.agents/README.md`
- `.agents/ORCHESTRATOR.md`
- `.agents/roles/contract-editor.md`
- `.agents/workflows/task-plan.md`
- `.agents/workflows/task-done.md`
- `docs/AGENT_CONTEXT_PACKETS.md`
- `docs/AGENT_GUIDE.md`
- `docs/AGENT_PIPELINE_ARCHITECTURE.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/AI_PROMPT_CONTRACTS.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/CI_STRATEGY.md`
- `docs/CLI_SPEC.md`
- `docs/DOGFOODING.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/DOCTEST_MUTATION_STRATEGY.md`
- `docs/GAP_REGISTRIES.md`
- `docs/HANDOFF_CONTRACTS.md`
- `docs/INTERNAL_API_CONTRACTS.md`
- `docs/INVARIANTS.md`
- `docs/MUTATOR_SPEC.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/PROJECT_ACCEPTANCE_CRITERIA.md`
- `docs/REPORT_FORMAT.md`
- `docs/SANDBOX_SECURITY.md`
- `docs/SEQUENTIAL_EXECUTION_POLICY.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/TDD_POLICY.md`
- `docs/TEST_SELECTION.md`
- `docs/ZIR_BACKEND.md`
- `docs/AIR_BACKEND.md`
- `schemas/ai.context.v1.schema.json`
- `tasks/schema/status.v1.schema.json`
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

- First add failing structural validator guardrails before implementation for the contracts in scope.
- Run `python3 scripts/validate_task_system.py` after adding the guardrails and record the expected failures before fixing contracts.

- After implementation, run:

   ```bash
   python3 -m py_compile scripts/validate_task_system.py
   python3 scripts/validate_task_system.py
   jq empty tasks/status.json tasks/queue.json tasks/schema/status.v1.schema.json
   git diff --check
   ```

## Acceptance criteria

- `clean_handoff_baseline` is defined in the status schema, synchronized in `tasks/status.json`, and validated by `scripts/validate_task_system.py`.
- Active and inactive changed-file scope validation are baseline-aware and still reject unbaselined changes.
- Agent-facing docs state exactly how task startup differs before and after task `041`.
- Downstream spec/task drifts listed in this task are closed with validator-readable phrases.
- Task-control Markdown and JSON remain synchronized.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Project bootstrap source creation.
- Runtime mutation behavior.
- New Zig tests or source modules.
- Implementing pipeline artifact writers, AI commands, dogfood execution, or full JSON Schema validation beyond structural task-system guardrails.

## Suggested implementation approach

1. Activate this prerequisite and run the existing validator.
2. Add validator guardrails first so the current contract drift fails.
3. Align status schema, validator behavior, docs, affected future task files, and gap rows.
4. Complete the task only after active-scope validation and final complete-state validation pass.

## Dogfooding implications

This task removes autonomous-agent blockers before any dogfoodable zentinel runtime exists. No zentinel dogfood run is expected.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
