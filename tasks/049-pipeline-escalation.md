# 049 Pipeline Escalation

Sequential guard: Start this task only after task `048` is complete and `tasks/status.json` names `049` as the next queued task.

## Goal

Finalize complexity escalation rules so each task class receives the correct pipeline depth, reviewers, mutation checks, property tests, doctests, and architecture review.

## Scope

- Refine `docs/PIPELINE_ESCALATION_POLICY.md`.
- Define low-risk, normal, high-risk, compiler-internal, and architecture task classes.
- Define escalation triggers from failed tests, survivors, source mapping changes, public contract changes, and performance regressions.
- Ensure escalation policy is referenced from the agent guide and orchestration spec.
- This task must refine the baseline escalation schema created by task `063` with final escalation outcomes, triggers, and monotonic gate evidence.

## Files allowed to modify

- `docs/PIPELINE_ESCALATION_POLICY.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/AGENT_ROLE_SPEC.md`
- `docs/AGENT_GUIDE.md`
- `docs/ROADMAP.md`
- `test/fixtures/pipeline/escalation/**`
- `schemas/pipeline.escalation.v1.schema.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing escalation fixture for a compiler-internal task missing Architecture Reviewer or Property Test Agent evidence.
- Run `python3 scripts/validate_task_system.py`.
- If validation tooling exists, validate each complexity class and at least one escalation trigger.

## Required property tests

If escalation validation code exists, add property-style tests proving stricter requirements are monotonic: escalating a task cannot remove required gates.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. Escalation examples must be deterministic and future-doctest compatible.

## Mutation testing requirements

No mutation run is required unless escalation validation code changes. Once mutation testing exists, mutation-test the complexity classifier and monotonic gate requirements.

## Acceptance criteria

- Complexity classes are explicit.
- Required pipeline depth for each class is explicit.
- Use both specialized roles only when both triggers apply.
- Escalation triggers and reviewer requirements are documented.
- The policy prevents architecture drift and broad refactors.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not implement an automated classifier.
- Do not add runtime orchestration.
- Do not relax sequential execution.

## Suggested implementation approach

1. Add a failing fixture for the highest-risk missing gate.
2. Update escalation, orchestration, and role docs consistently.
3. Confirm the policy remains compatible with sequential task locking.
4. Record validation output and follow-up work.

## Dogfooding implications

Escalation rules determine when zentinel's own development tasks require mutation gates, property evidence, doctest evidence, or architecture review.

## Follow-up tasks

- `tasks/064-pipeline-artifact-ci-integration.md`
