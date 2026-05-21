# 094 Agent Readiness Validator Closure

Sequential guard: start this task only after task `093` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Close the remaining autonomous-agent readiness gaps before project bootstrap by aligning validator guardrails, task scope, lifecycle docs, and staged product contracts.

## Scope

- Strengthen task-system validation for completed-task file scope, blocked-task recovery, status metadata, and post-041 artifacts.
- Clarify lifecycle and role-routing contracts so queue states and pipeline artifact stages do not conflict.
- Clarify staged product contracts for safety-mode report schema ownership, mutant classification evidence, Phase 2 mutator expansion, impact graph availability, runner evidence bounds, backend version visibility, doctest AI stubs, and plain `zig` doctest expectations.
- Keep the repository Codex-only and preserve the pinned Zig `0.16.0` and AST-default contracts.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/007-mutant-model.md`
- `tasks/015-mutant-runner.md`
- `tasks/020-test-selection-same-file.md`
- `tasks/051-fail-fast-impact-analysis.md`
- `tasks/055-ai-doctest-assistance.md`
- `tasks/058-safety-mode-matrix.md`
- `tasks/067-ai-doctest-survivor-assistance.md`
- `tasks/094-agent-readiness-validator-closure.md`
- `tasks/schema/status.v1.schema.json`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/TDD_POLICY.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/PIPELINE_ESCALATION_POLICY.md`
- `docs/GAP_REGISTRIES.md`
- `docs/CONFIG_SPEC.md`
- `docs/MUTATOR_SPEC.md`
- `docs/TEST_SELECTION.md`
- `docs/REPORT_FORMAT.md`
- `docs/SANDBOX_SECURITY.md`
- `docs/AI_PROMPT_CONTRACTS.md`
- `docs/DOCTEST_BLOCK_FORMATS.md`
- `docs/DOCTEST_ARCHITECTURE.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/INTERNAL_API_CONTRACTS.md`
- `schemas/report.v1.schema.json`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `.claude/**`

## Required tests

- First add a failing structural validator guardrail for the documented autonomous-agent gaps from the four-lane analysis.
- Run `python3 scripts/validate_task_system.py` after adding the new guardrails and record the expected failures before fixing contracts.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for edited JSON files.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Completed-task evidence for task `094` and later is concrete enough for the validator to check changed files against task scope after completion.
- Blocked-task metadata requires an executable prerequisite unless user input is explicitly required, and completed prerequisites cannot leave the blocked task stranded.
- Queue lifecycle docs treat `implemented` and `verified` as pipeline artifact stages, not normal task-control states.
- Role-routing docs agree on low-risk, normal, high-risk, compiler-internal, and architecture task minimums.
- Task `058` can satisfy safety-mode report work without violating allowed-file scope.
- Mutant classification, Phase 2 mutator expansion, impact graph staging, runner evidence bounds, backend-version visibility, doctest AI stubs, and plain `zig` doctest expectation rules are explicit enough for autonomous implementation.
- `tasks/STATUS.md` records completion, files changed, tests run, and no prose-only follow-up.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Project bootstrap source creation.
- Runtime mutation behavior.
- New Zig tests or source modules.
- Implementing doctest, AI, cache, runner, or safety-mode code.

## Suggested implementation approach

1. Add validator checks first so the current contracts fail for the known gaps.
2. Align docs, task files, schemas, and validator guardrails in small commits.
3. Keep schema changes additive within the existing pre-bootstrap task-system contract.
4. Complete the task only after active-scope validation and final complete-state validation pass.

## Dogfooding implications

This task removes autonomous-agent blockers before any dogfoodable zentinel runtime exists. No zentinel dogfood run is expected.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
