# Failure Recovery

Failure recovery keeps sequential work safe and reproducible.

## Failed Implementation

If implementation fails approved tests:

1. Preserve failing output.
2. Re-check test validity.
3. Attempt bounded fix within task scope.
4. Escalate after retry limit.

Do not weaken tests.

## Failed Mutation Gate

If mutation gate fails:

- invalid mutants block immediately
- baseline failure returns to implementation
- survivors go to triage
- missing tests return to Test Author
- equivalent-risk claims require evidence

These map to the `blocking_reasons` in the gate report (`artifacts/pipeline/<task-id>/mutation/report.json`) defined by `docs/MUTATION_GATE_POLICY.md`: `baseline failure`, `invalid mutants present`, `nondeterministic mutation report`, and `untriaged survivor <mutant_id>`. The Retry Limits table below is the same one in that policy; an exceeded limit or a `tooling_bug` / `needs_architecture_review` classification escalates to architecture or contract review instead of retrying.

## Flaky Verification

A flaky result is a failure until proven otherwise.

Recovery:

1. Repeat command with same seed and config.
2. Capture both outputs.
3. Identify nondeterministic field.
4. Add normalization or deterministic ordering test.
5. Rerun verifier.

## Stale Lock

A stale active-task lock (`docs/SEQUENTIAL_EXECUTION_POLICY.md`) is a failure that blocks completion until recovered:

- the synchronized task-control files are authoritative over the lock
- replace the lock to match the true active task, or remove it when no task is active
- record the recovery in the verifier report `residual_risk` or the completion summary so it is auditable
- never resolve a lock conflict by activating a second task

## Rollback Rules

Agents may revert only their own incomplete edits.

Never revert unrelated user changes.

If partial edits are useful but incomplete:

- keep them behind failing tests only if task remains active
- otherwise revert own edits and create follow-up task

## Retry Limits

| Task class | Retry cycles |
| --- | --- |
| Low-risk | 1 |
| Normal | 2 |
| High-risk | 3 |
| Compiler-internal | 3 plus architecture review |
| Architecture | 1 plus contract review |
