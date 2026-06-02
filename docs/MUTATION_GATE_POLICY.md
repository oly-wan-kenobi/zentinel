# Mutation Gate Policy

Mutation testing is a verification gate after implementation review and before final verification.

## Gate Position

```text
Tests
  -> Implementation
  -> Review
  -> Mutation Gate
  -> Survivor Triage
  -> Final Verification
```

## Required When

Task `043` is the mutation-gate availability cutover. Before task `043` is complete, mutation-gate skip reasons must use `pre-gate unavailable` when the active task changes behavior that would otherwise require the gate but the gate cannot exist yet. The skip reason must name the missing prerequisite and must not claim mutation evidence was run.

After task `043` is complete, mutation gate is mandatory for mutation-testable tasks only when the active scope is mutation-testable and the required runner/report surface exists for that scope. Mutation gate is required for:

- mutator implementation
- runner behavior
- report classification
- config validation with meaningful branches
- test selection
- cache key behavior
- doctest mutation features
- dogfood-sensitive core modules

Mutation gate may be skipped for:

- pure documentation tasks before doctests exist
- task metadata changes
- schema-only tasks with no executable behavior

Skip requires a written reason.

## Blocking Conditions

The gate blocks completion on:

- invalid mutants
- baseline failure
- nondeterministic mutation reports
- new survivors in protected dogfood scope
- untriaged survivors for the active task

Survivors outside protected scope may produce follow-up tasks instead of blocking, but only after triage.

## Survivor Classification

Allowed classifications:

```text
missing_test
weak_assertion
equivalent_risk
compile_mode_specific
fixture_gap
tooling_bug
out_of_scope
needs_architecture_review
```

AI may suggest classification. The triage artifact owns the final advisory classification.

## Equivalent Mutants

Equivalent mutant handling must be conservative.

Rules:

- do not mark equivalent automatically unless a deterministic rule exists
- document evidence
- create follow-up task when uncertain
- never remove survivor evidence from report

## Retry Behavior

If survivors indicate missing tests:

1. Return to Test Author.
2. Add failing test for survivor behavior.
3. Review test.
4. Implement if needed.
5. Rerun mutation gate.

Retry limit:

- low-risk: 1 cycle
- normal: 2 cycles
- high-risk: 3 cycles
- compiler-internal: 3 cycles plus architecture review
- architecture: 1 cycle plus contract review

These retry limits are the same ones recorded in `docs/FAILURE_RECOVERY.md` (and enforced by `FAILURE_RECOVERY_RETRY_LIMITS` in `scripts/validate_task_system.py`); the two documents must not diverge.

## Escalation

The gate escalates instead of retrying when:

- the retry limit for the task class is reached and survivors remain
- a survivor is classified `tooling_bug` or `needs_architecture_review`
- mutation reports are nondeterministic across identical seed and config
- a compiler-internal crash recurs after the compiler-internal retry budget

Escalation produces an escalation artifact (`zentinel.pipeline.escalation.v1`, refined by task `049`) and routes to architecture or contract review per `docs/FAILURE_RECOVERY.md`. AI may advise but never waives a survivor or closes an escalation.

## Gate Report Artifact

The mutation gate records its decision in `artifacts/pipeline/<task-id>/mutation/report.json`. Task `043` defines this contract and ships example artifacts; the durable JSON Schema and `docs/SCHEMA_REGISTRY.md` row land with the runtime verification pipeline, so no schema file is registered yet.

```json
{
  "schema_version": "zentinel.pipeline.mutation_gate.v1",
  "task_id": "043",
  "scope": "mutation_testable",
  "gate_status": "passed",
  "baseline": { "status": "completed" },
  "deterministic": true,
  "summary": {
    "total": 5,
    "killed": 3,
    "survived": 1,
    "compile_error": 1,
    "compiler_crash": 0,
    "timeout": 0,
    "invalid": 0,
    "skipped": 0
  },
  "survivors": [
    {
      "mutant_id": "m_8kjyy9kdjw9zngpb31q659cqmt",
      "status": "survived",
      "triage": {
        "classification": "out_of_scope",
        "advisory": true,
        "evidence": "survivor is in an unrelated module outside the active task scope",
        "follow_up_task": "tasks/046-verification-pipeline.md"
      }
    }
  ],
  "blocking_reasons": [],
  "retry": { "task_class": "normal", "cycle": 0, "limit": 2 },
  "recommendation": "follow_up"
}
```

Field rules:

- `scope` is `mutation_testable` or `not_mutation_testable`. A `not_mutation_testable` scope replaces the pre-cutover `pre-gate unavailable` skip reason with a written `skip_reason`.
- `summary` counts the six terminal mutant statuses `killed`, `survived`, `compile_error`, `compiler_crash`, `timeout`, `invalid` plus `skipped`; the seven counts must sum to `total`, and `survivors` must list exactly the `survived` mutants.
- `gate_status` is derived deterministically, not chosen. The gate is `blocked` if and only if at least one of these holds, and every reason that holds appears in `blocking_reasons`:
  - `baseline.status` is `baseline_failed` (reason `baseline failure`)
  - `summary.invalid` is greater than zero (reason `invalid mutants present`)
  - `deterministic` is `false` (reason `nondeterministic mutation report`)
  - any survivor has no triage, i.e. `triage` is `null` or its `classification` is absent (reason `untriaged survivor <mutant_id>`)
- Otherwise `gate_status` is `passed`. A survivor classified for follow-up does not by itself block; an untriaged survivor always blocks.
- `triage.classification`, when present, must be one of the classifications listed above. Classification stays advisory; it never lets AI waive a survivor.
- `retry.limit` must equal the limit for `retry.task_class` from the retry table, and `retry.cycle` may not exceed it.

Because `gate_status` and `blocking_reasons` are derived from the survivor set and summary, survivor ordering cannot change the decision.
