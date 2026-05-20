# 065 Failure Recovery Validator

Sequential guard: start this task only after task 064 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Validate failure-recovery task and artifact states so failed gates cannot be marked complete without auditable recovery evidence.

## Scope

- Add validation fixtures for retry exhaustion, blocked tasks, rollback-required states, and stale context.
- Reject invalid lifecycle transitions documented by `docs/FAILURE_RECOVERY.md`.
- Connect recovery validation to task lifecycle and pipeline artifacts.
- Preserve user-owned changes during rollback documentation.

## Files allowed to modify

- `scripts/validate_task_system.py`
- `docs/FAILURE_RECOVERY.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/VERIFICATION_PIPELINE.md`
- `test/fixtures/pipeline/failure_recovery_validator/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing validation fixture for `failed mutation gate -> complete`.
- Add a failing validation fixture for retry exhaustion without a blocked task or recovery artifact.
- Add a failing validation fixture for rollback-required state missing changed-file evidence.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Invalid recovery transitions fail validation with stable diagnostics.
- Recovery artifacts distinguish agent-owned edits from pre-existing user edits.
- Retry exhaustion cannot be hidden by marking a task complete.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Automated rollback commands.
- Git history rewriting.
- Suppressing failing verification.

## Suggested implementation approach

1. Encode the invalid transition fixtures first.
2. Extend validator checks narrowly around documented recovery states.
3. Keep rollback evidence path-based and project-relative.
4. Re-run the full task-system validator after each rule.

## Dogfooding implications

Recovery validation keeps dogfood failures and survivor triage from becoming unverifiable prose.

## Follow-up tasks

- `tasks/066-public-docs-doctest-coverage.md`
