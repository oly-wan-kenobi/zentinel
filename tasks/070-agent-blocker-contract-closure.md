# 070 Agent Blocker Contract Closure

Sequential guard: start this task only after task 069 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Resolve the preimplementation agent-blocking contract findings before project bootstrap begins.

## Scope

- Close the bootstrap build-test discovery gap before tasks 001 and 002 add tests.
- Define the post-041 active-lock pipeline artifact path and required fields.
- Make follow-up task validation use execution order, not numeric task ID order alone.
- Clarify doctest expectation blocks as secondary blocks instead of standalone report cases.
- Refresh stale current status prose and add a minimal repository README entry point.
- Add validator guardrails for the resolved contract classes.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/070-agent-blocker-contract-closure.md`
- `README.md`
- `scripts/validate_task_system.py`
- `docs/SCHEMA_REGISTRY.md`
- `tests/coverage-gaps/schemas.v1.json`
- `tasks/000-project-bootstrap.md`
- `tasks/003-test-harness.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/047-sequential-task-locking.md`
- `tasks/049-pipeline-escalation.md`
- `tasks/062-property-generator-infrastructure.md`
- `tasks/063-pipeline-metadata-validator.md`
- `docs/DOCTEST_SPEC.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/SEQUENTIAL_EXECUTION_POLICY.md`
- `docs/AGENT_ROLE_SPEC.md`
- `docs/VERIFICATION_PIPELINE.md`
- `.agents/README.md`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `docs/MUTATOR_SPEC.md`
- `.claude/**`

## Required tests

- Add failing structural validator guardrails for follow-up execution order and the resolved preimplementation contracts before changing the contracts.
- Run `python3 scripts/validate_task_system.py` and record the expected pre-fix failure.
- Run `python3 scripts/validate_task_system.py` after contract fixes.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for task state files.
- Run `git diff --check`.

## Acceptance criteria

- Task 000 owns enough build-test discovery for task 001 and task 002 test files to be included by `zig build test` without per-task `build.zig` edits.
- Post-041 active lock artifacts have a deterministic path and required fields documented in pipeline contracts.
- Follow-up task references cannot point to earlier execution-order tasks.
- Doctest `text output` and `json expected` blocks are unambiguously secondary expectation blocks, not standalone `case.kind` report entries.
- Current status prose and README orientation no longer mislead agents about the current backlog shape.
- Historical task status entries avoid stale exact task-count claims.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not implement Zig project files.
- Do not implement pipeline artifact writers.
- Do not add doctest runtime code.
- Do not change product report schemas.
- Do not add dependencies.

## Suggested implementation approach

1. Add validator checks that fail against the existing ambiguous contracts.
2. Update task and docs contracts in the smallest compatible way.
3. Keep task-control Markdown and JSON synchronized.
4. Run validator and syntax checks.

## Dogfooding implications

This task removes contract ambiguity before zentinel can dogfood itself. No dogfood run is expected yet.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
