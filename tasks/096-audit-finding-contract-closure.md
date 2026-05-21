# 096 Audit Finding Contract Closure

Sequential guard: start this task only after task `095` is complete in `tasks/STATUS.md`. Task `000` is blocked until this prerequisite completes, because the latest four-agent audit found remaining autonomous-agent implementation blockers in test-selection safety, pipeline handoffs, AI schemas, report semantics, and task lifecycle wording.

## Goal

Close the remaining repo-audit findings that could cause autonomous agents to implement zentinel inconsistently before project bootstrap begins.

## Scope

- Clarify that generated same-file selected test commands are authorized only after unmutated preflight evidence.
- Fix the post-`041` pipeline artifact scope exception in the task-system validator.
- Add the missing canonical `Planner` role definition.
- Align AI prompt examples and AI context schema bounds with registered schemas and sandbox limits.
- Align follow-up task timing, queued-state terminology, high-risk routing, report semantic validation, CLI output bounds, and future mode-matrix report compatibility.
- Preserve pinned Zig `0.16.0`, AST-default behavior, deterministic core authority, and Codex-only agent contracts.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/006-report-schema.md`
- `tasks/016-minimal-run-command.md`
- `tasks/020-test-selection-same-file.md`
- `tasks/040-agent-pipeline-foundation.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/049-pipeline-escalation.md`
- `tasks/053-ai-provider-and-context.md`
- `tasks/054-ai-advisory-commands.md`
- `tasks/058-safety-mode-matrix.md`
- `tasks/096-audit-finding-contract-closure.md`
- `docs/ARCHITECTURE.md`
- `docs/TEST_SELECTION.md`
- `docs/SANDBOX_SECURITY.md`
- `docs/AGENT_ROLE_SPEC.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/PIPELINE_ESCALATION_POLICY.md`
- `docs/AGENT_PIPELINE_ARCHITECTURE.md`
- `docs/AI_PROMPT_CONTRACTS.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/REPORT_FORMAT.md`
- `docs/CLI_SPEC.md`
- `docs/CONFIG_SPEC.md`
- `schemas/ai.context.v1.schema.json`
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
- Run JSON syntax checks for edited JSON files.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` while task `096` is still active.
- Run `python3 scripts/validate_task_system.py` again after marking task `096` complete.

## Acceptance criteria

- Generated same-file selected commands require unmutated preflight evidence before they can classify a mutant.
- The validator accepts task-scoped `artifacts/pipeline/<active-task-id>/**` completion evidence after task `041` is complete by checking against the full task list.
- `Planner` is defined in `docs/AGENT_ROLE_SPEC.md` consistently with orchestrator and handoff contracts.
- AI prompt examples contain command `failure_kind`, and AI context stdout/stderr excerpts are bounded to 4096 characters in schema and task requirements.
- Follow-up tasks are recorded while the original task is still active, before active validation and completion.
- `queued` wording distinguishes all queued future tasks from dependency-ready queued tasks.
- High-risk routing consistently adds Property Test Agent or Mutation Agent as applicable, using both only when both triggers apply.
- Report semantic validation must reject lifecycle-invalid `internal_error` shapes where `baseline.status = "not_run"` coexists with mutant entries.
- Explicit CLI `--output <path>` inherits the project-root path bound used by config `report.output_dir`.
- Task `058` has an explicit additive `report.v1` mode-matrix compatibility rule.
- `tasks/STATUS.md` records completion, files changed, tests run, and no prose-only follow-up.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Project bootstrap source creation.
- Runtime mutation behavior.
- New Zig tests or source modules.
- Implementing AI providers, doctests, report writers, runner execution, or pipeline artifact tooling.

## Suggested implementation approach

1. Add validator checks first so the current drift fails.
2. Align docs, schemas, affected future task files, and validator behavior.
3. Keep schema changes additive within the existing v1 contracts.
4. Complete the task only after active-scope validation and final complete-state validation pass.

## Dogfooding implications

This task removes autonomous-agent blockers before any dogfoodable zentinel runtime exists. No zentinel dogfood run is expected.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
