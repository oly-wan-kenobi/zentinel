# 093 Agent Enforcement Closure

Sequential guard: start this task only after task `092` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Close the latest parallel-agent findings before project bootstrap so autonomous agents inherit machine-checkable enforcement instead of prose-only assumptions.

## Scope

- Add structural validator guardrails for completion-order wording, blocked-task recovery metadata, completion evidence shape, gap registry closure, post-`041` artifact references, and source-reference freshness wording.
- Clarify task completion workflow so final changed-file scope validation runs while the task is still active.
- Clarify blocked-task recovery as a queued-state transition after prerequisite completion, with typed blocker metadata.
- Tighten future completion evidence and pipeline artifact references without retroactively invalidating completed documentation-only hardening tasks.
- Clarify pre-task-`058` safety mode behavior, doctest exit-code semantics, mutation result classification authority, backend version identity, property evidence cutovers, and doctest source-reference derivation.
- Align affected queued task specs so implementation agents see the corrected requirements locally.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/093-agent-enforcement-closure.md`
- `tasks/000-project-bootstrap.md`
- `tasks/001-cli-shell.md`
- `tasks/002-config-parser.md`
- `tasks/006-report-schema.md`
- `tasks/007-mutant-model.md`
- `tasks/021-cache-key-design.md`
- `tasks/033-doctest-runner.md`
- `tasks/035-cli-doctests.md`
- `tasks/058-safety-mode-matrix.md`
- `tasks/schema/status.v1.schema.json`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/TDD_POLICY.md`
- `docs/CONFIG_SPEC.md`
- `docs/CLI_SPEC.md`
- `docs/DOCTEST_SPEC.md`
- `docs/DOCTEST_ARCHITECTURE.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/REPORT_FORMAT.md`
- `docs/INTERNAL_API_CONTRACTS.md`
- `docs/GAP_REGISTRIES.md`
- `docs/PROPERTY_TEST_POLICY.md`
- `docs/VERIFICATION_PIPELINE.md`
- `docs/ARCHITECTURE.md`
- `docs/PERFORMANCE_STRATEGY.md`
- `docs/DISCIPLINE.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `.agents/workflows/task-done.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/report.v1.schema.json`
- `.claude/**`

## Required tests

- Add failing validator guardrails for active-before-complete scope wording, blocked-task recovery metadata, future completion evidence shape, post-`041` artifact references, stale doctest source-reference wording, task `058` safety-mode staging, doctest failure exit semantics, classifier-authority wording, backend version identity, and gap registry closure.
- Run `python3 scripts/validate_task_system.py` after adding the guardrails and record the expected failure before contract updates.
- Run `python3 scripts/validate_task_system.py` after implementation.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for edited JSON files.
- Run `git diff --check`.

## Acceptance criteria

- Task completion docs require changed-file scope validation while the task is still active, before queue/status completion state is cleared.
- Blocked-task recovery docs and status schema require typed blocker metadata and define return-to-queued recovery after prerequisite completion.
- Completed-task evidence remains compatible with historical docs-only tasks while future evidence has stricter validator-backed shape and artifact reference slots.
- Pre-task-`058` configuration docs reject multiple simultaneous safety modes until the safety matrix task exists.
- Doctest docs and CLI docs agree on deterministic doctest failure exit semantics.
- Mutation result classification docs make deterministic classifier evidence authoritative and do not allow AI judgment to classify correctness.
- Backend version docs define a deterministic AST backend version string under the pinned Zig `0.16.0` policy.
- Gap registry docs and validator guardrails reject uncovered rows deferred to already-complete tasks unless the row is explicitly superseded.
- Property and pipeline docs state the task `062` cutover between fixture-based property evidence and generated property evidence.
- Doctest source-reference examples cannot be copied as stale hard-coded line references.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing product runtime behavior.
- Changing public report v1 schema shape.
- Adding Zig source, build files, or runtime tests.
- Implementing safety modes, doctest execution, mutation classification, backend caching, or pipeline artifact writers.

## Suggested implementation approach

1. Add validator guardrails first and confirm they fail on the current contracts.
2. Update docs, task specs, and the status schema to satisfy those guardrails.
3. Keep report v1 schema unchanged; express classifier provenance through documented evidence fields and future task requirements.
4. Update task status and completion evidence only after validation passes while task `093` remains active.

## Dogfooding implications

This task removes autonomous-agent blockers before dogfoodable product code exists. No zentinel dogfood run is expected yet.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
