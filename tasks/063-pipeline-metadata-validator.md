# 063 Pipeline Metadata Validator

Sequential guard: start this task only after task 041 is complete in `tasks/STATUS.md`. This task runs immediately after task 041 so later pipeline tasks rely on validator-backed JSON artifacts.

## Goal

Validate pipeline metadata artifacts so handoffs, context packets, reviews, and verification reports cannot silently drift from their schemas.

## Scope

- Extend validation for pipeline artifact directories after task 041.
- Execute immediately after task 041, before context-packet, mutation-gate, verification, recovery, or CI pipeline tasks consume JSON handoff artifacts.
- Consume and validate baseline pipeline schema files created by task `041`; task `063` must consume and validate baseline pipeline schema files created by task `041`, not create them.
- The baseline pipeline schema files contain only the required fields already documented by the current contracts; tasks `042`, `046`, and `049` refine context/stale-context, verification, and escalation semantics without weakening task `063` validation.
- Validate required JSON handoffs, context packets, active lock artifact records, stale-context markers, escalation records, and verification records when present.
- Implement a project-owned schema subset validator for pipeline artifacts: `schema_version`, required fields, additional-property policy, enum and const checks, basic string/integer/boolean/null/object/array shapes, and task/path ownership.
- Reject Markdown-only handoffs after the JSON handoff cutover.
- Keep validation deterministic and standard-library-only unless a task explicitly adds a dependency.
- Do not claim full Draft 2020-12 support for conditionals, arbitrary `$ref` traversal, or derived invariants unless a later task approves a schema-validation dependency or expands the supported subset.

## Files allowed to modify

- `scripts/validate_task_system.py`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/HANDOFF_CONTRACTS.md`
- `docs/AGENT_CONTEXT_PACKETS.md`
- `schemas/pipeline.handoff.v1.schema.json`
- `schemas/pipeline.active_lock.v1.schema.json`
- `schemas/pipeline.context.v1.schema.json`
- `schemas/pipeline.stale_context.v1.schema.json`
- `schemas/pipeline.verification.v1.schema.json`
- `schemas/pipeline.escalation.v1.schema.json`
- `test/fixtures/pipeline/metadata_validator/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing fixture where a post-041 task has a Markdown handoff without the required JSON handoff.
- Add a failing fixture where a pipeline JSON artifact is missing a required schema field.
- Add a failing fixture where `locks/active-task-lock.json` names a different task than its artifact directory or context packet.
- Add a failing fixture where a pipeline JSON artifact has an unknown field rejected by the artifact schema subset.
- Add a failing fixture where enum or const values, including `schema_version`, do not match the registered pipeline schema.
- Add a failing fixture where an artifact is written under the wrong task ID.
- Add failing metadata fixtures that validate I-019 chronology by checking pipeline artifact role timestamps.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Pipeline artifact validation is deterministic and task-scoped.
- Pipeline metadata validation is in place immediately after task 041 introduces durable handoff artifacts.
- Baseline pipeline schema files from task `041` are consumed by the validator before tasks `042`, `046`, and `049` refine role-specific fields. Task `063` may tighten schema validation or fixtures across all baseline pipeline schemas but must not create them.
- The validator can validate I-019 chronology by checking pipeline artifact role timestamps once durable role handoffs exist.
- Validator documentation states the supported schema subset and does not imply full Draft 2020-12 support.
- JSON handoffs are required after task 041 for non-trivial tasks.
- The post-041 active lock artifact at `locks/active-task-lock.json` is validated against task and context-packet ownership.
- Wrong-task artifact paths are rejected.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Runtime orchestration.
- Subagent spawning.
- CI script integration.

## Suggested implementation approach

1. Add fixture directories that simulate valid and invalid artifact trees.
2. Validate paths and required fields before adding deeper semantic checks.
3. Keep error messages stable and actionable.
4. Preserve existing task-system validation behavior.

## Dogfooding implications

Pipeline metadata validation keeps long-running dogfood and release work restartable by fresh agents.

## Follow-up tasks

- `tasks/064-pipeline-artifact-ci-integration.md`
