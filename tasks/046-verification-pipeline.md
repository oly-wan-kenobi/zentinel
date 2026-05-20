# 046 Verification Pipeline

Sequential guard: Start this task only after task `045` is complete and `tasks/status.json` names `046` as the next queued task.

## Goal

Specify the final verification pipeline that decides whether a task can move from implemented to verified and complete.

## Scope

- Refine `docs/VERIFICATION_PIPELINE.md`.
- Define required order for unit tests, property tests, doctests, mutation checks, dogfood checks, snapshot checks, performance checks, and task-system validation.
- Define fail-fast behavior and report generation.
- Connect verification artifacts to task status updates.
- This task must refine the baseline verification schema created by task `063` with the final verifier fields and fixture expectations.

## Files allowed to modify

- `docs/VERIFICATION_PIPELINE.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/CI_STRATEGY.md`
- `docs/AGENT_GUIDE.md`
- `test/fixtures/pipeline/verification/**`
- `schemas/pipeline.verification.v1.schema.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing verification artifact fixture for a missing required command result.
- Run `python3 scripts/validate_task_system.py`.
- If validation tooling exists, validate pass, fail-fast, skipped-not-applicable, and blocked verification states.

## Required property tests

If verification validation code exists, add property-style tests proving command ordering is stable and duplicate stage names are rejected deterministically.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. Verification examples must be snapshot-friendly.

## Mutation testing requirements

No product mutation run is required unless verification code changes. Once mutation testing exists, mutation-test the stage classifier and fail-fast branches.

## Acceptance criteria

- Verification order is explicit.
- Fail-fast rules are explicit.
- Every stage has required artifact fields.
- CI integration expectations are documented around the canonical `scripts/ci.sh` entrypoint.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not add hosted CI workflow files.
- Do not implement command runners.
- Do not introduce performance benchmarks.

## Suggested implementation approach

1. Add a failing fixture for incomplete verifier evidence.
2. Update verification and artifact docs.
3. Cross-check lifecycle transitions for implemented, verified, complete, and blocked states.
4. Run validation and record evidence.

## Dogfooding implications

This task defines the verification order that later dogfood tasks must follow before completion.

## Follow-up tasks

- `047-sequential-task-locking.md`
- `048-failure-recovery.md`
