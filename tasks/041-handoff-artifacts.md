# 041 Handoff Artifacts

Sequential guard: Start this task only after task `040` is complete and `tasks/status.json` names `041` as the next queued task.

## Goal

Define and validate the persistent handoff artifact structure used between pipeline roles so stateless agents can continue a task without hidden conversation history.

## Scope

- Refine `docs/HANDOFF_CONTRACTS.md` and `docs/PIPELINE_ARTIFACTS.md`.
- Define JSON artifact fields for each pipeline role and optional Markdown companion summaries.
- Specify artifact naming, retention, traceability, and reproducibility rules.
- Define the active lock artifact path `locks/active-task-lock.json` and its required fields.
- Add schema documentation only; do not implement a runtime writer.

## Files allowed to modify

- `docs/HANDOFF_CONTRACTS.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/AGENT_GUIDE.md`
- `schemas/pipeline.handoff.v1.schema.json`
- `schemas/pipeline.active_lock.v1.schema.json`
- `test/fixtures/pipeline/handoff/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing schema or fixture validation case before adding or changing the handoff schema.
- If project-owned schema validation tooling does not exist yet, use a deterministic external schema or fixture validation command and record the exact command in completion evidence.
- Run `python3 scripts/validate_task_system.py`.
- If schema validation tooling exists, validate a passing and failing handoff artifact fixture.

## Required property tests

If schema validation code exists, add a deterministic property-style test that removes one required field at a time and proves each invalid artifact is rejected with a stable diagnostic.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. Handoff examples in docs must be deterministic and ready to become `json expected` or `text output` blocks later.

## Mutation testing requirements

No mutation run is required unless schema validation code is changed. If code is changed in a future revision, run mutation checks for required-field validation.

## Acceptance criteria

- Each pipeline role has a required handoff artifact.
- Handoff docs define deterministic handoff names for every emitting role, including orchestration, task-state transitions, review, mutation, property, doctest, architecture, and verification roles.
- The active lock artifact is documented at `locks/active-task-lock.json` with deterministic task, queue, context packet, and working-tree evidence.
- Artifact fields include files changed, tests added, commands executed, risks, assumptions, mutation results, and next-step instructions.
- Document that tests_added is cumulative task-level evidence; role-local test changes are documented in the role-specific content or command evidence.
- Machine-readable JSON handoffs are documented as the canonical artifact with required and optional fields.
- Artifact names are deterministic and task-scoped.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not build artifact persistence commands.
- Do not implement orchestrator integration.
- Do not change product report schemas.

## Suggested implementation approach

1. Add a failing schema fixture for the minimum required handoff artifact.
2. Update the handoff docs and schema together.
3. Add one passing example per role and one failing example for missing required fields.
4. Run validators and record the command output.

## Dogfooding implications

Future dogfood runs will archive these artifacts for survivor triage and release review. This task defines the shape only.

## Follow-up tasks

- `tasks/063-pipeline-metadata-validator.md`
- `tasks/042-context-packet-system.md`
- `tasks/046-verification-pipeline.md`
