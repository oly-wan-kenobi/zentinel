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

## Recovery Transitions

Recovery is a deterministic state machine, not an ad hoc decision. Each step is recorded as a transition artifact (`zentinel.pipeline.failure_recovery_transition.v1`) with auditable evidence:

```json
{
  "schema_version": "zentinel.pipeline.failure_recovery_transition.v1",
  "task_id": "048",
  "from_state": "failed_mutation_gate",
  "trigger": "out_of_scope_survivor",
  "to_state": "follow_up_created",
  "retry": { "task_class": "normal", "cycle": 1, "limit": 2 },
  "evidence": "survivor triaged out_of_scope; follow-up task queued",
  "auditable": true
}
```

Only these transitions are valid:

| From | Trigger | To |
| --- | --- | --- |
| active | required_stages_passed | complete |
| active | required_stage_failed | failed_implementation |
| active | mutation_gate_blocked | failed_mutation_gate |
| active | flaky_result | flaky_verification |
| active | blocker_detected | blocked |
| failed_implementation | bounded_fix_within_limit | active |
| failed_implementation | retry_limit_exhausted | escalated |
| failed_implementation | unrelated_user_edits | rollback_required |
| failed_mutation_gate | missing_tests | return_to_role |
| failed_mutation_gate | out_of_scope_survivor | follow_up_created |
| failed_mutation_gate | needs_architecture_review | escalated |
| failed_mutation_gate | invalid_mutants / baseline_failure | failed_implementation |
| flaky_verification | reproduced_deterministic | failed_implementation |
| flaky_verification | normalized_and_passed | active |
| blocked | prerequisite_complete | active |
| rollback_required | agent_edits_reverted | blocked / follow_up_created |
| return_to_role | tests_added | active |
| follow_up_created | follow_up_queued | complete |
| escalated | reviewer_resolution | active / blocked |

Deterministic invariants:

- A failure state never transitions directly to `complete`; the canonical rejected transition is `failed_mutation_gate -> complete`. Completion is reached only from `active` with all required stages passed, or from `follow_up_created` once the follow-up is queued.
- A `flaky_verification` result is never `waived`; it transitions only by reproducing the deterministic failure or by adding normalization and passing.
- `rollback` may only have `scope` `agent_owned`; reverting pre-existing user edits is not a valid recovery.
- When `retry.cycle` exceeds `retry.limit` (from the Retry Limits table above), the only valid transition is to `escalated`.
- Every transition records non-empty `evidence` so the recovery is auditable.

These states map to task-control state in `docs/TASK_LIFECYCLE.md`: only `blocked` is a task-control state; `failed_implementation`, `failed_mutation_gate`, `flaky_verification`, `rollback_required`, `escalated`, `return_to_role`, and `follow_up_created` are recovery artifact stages inside the `active` task-control state. The retry limits, mutation-gate `blocking_reasons`, and escalation triggers reuse `docs/MUTATION_GATE_POLICY.md`, `docs/VERIFICATION_PIPELINE.md`, and `docs/PIPELINE_ESCALATION_POLICY.md`.
