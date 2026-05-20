# 048 Failure Recovery

Sequential guard: Start this task only after task `047` is complete and `tasks/status.json` names `048` as the next queued task.

## Goal

Specify deterministic recovery behavior for failed implementation, failed mutation gates, flaky verification, blocked tasks, and rollback of agent-owned changes.

## Scope

- Refine `docs/FAILURE_RECOVERY.md`.
- Define retry limits, escalation triggers, rollback rules, and artifact requirements.
- Connect recovery states to task lifecycle and sequential locking.
- Define how flaky tests are handled without masking deterministic failures.

## Files allowed to modify

- `docs/FAILURE_RECOVERY.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/PIPELINE_ESCALATION_POLICY.md`
- `docs/MUTATION_GATE_POLICY.md`
- `docs/VERIFICATION_PIPELINE.md`
- `test/fixtures/pipeline/failure_recovery/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing recovery fixture for one invalid transition, such as `failed mutation gate -> complete`.
- Run `python3 scripts/validate_task_system.py`.
- If validation code exists, validate retry exhaustion, blocked task, stale context, and rollback-required states.

## Required property tests

If lifecycle validation code exists, add property-style tests proving invalid recovery transitions are rejected across generated task states.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. Failure examples must normalize paths, durations, and command output.

## Mutation testing requirements

No mutation run is required unless recovery validation code changes. Once mutation testing exists, mutation-test retry-limit and fail-fast branches.

## Acceptance criteria

- Recovery paths are deterministic.
- Retry limits are explicit.
- Rollback rules distinguish agent-owned edits from pre-existing user edits.
- Flaky verification cannot be waived silently.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not add automated rollback commands.
- Do not change git history.
- Do not suppress failing tests.

## Suggested implementation approach

1. Add a failing transition fixture.
2. Update recovery and lifecycle docs.
3. Cross-check mutation gate and verification docs for matching terminology.
4. Record validation output and unresolved risks.

## Dogfooding implications

Dogfood failures must route through this policy so survivors, flaky checks, and invalid mutants become auditable follow-up work.

## Follow-up tasks

- `049-pipeline-escalation.md`
- `tasks/065-failure-recovery-validator.md`
