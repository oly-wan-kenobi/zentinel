# Verification Pipeline

The verification pipeline is the final authority for task completion.

## Required Order

```text
1. task-system validation
2. targeted unit tests
3. broader unit tests
4. property tests
5. doctests
6. snapshot verification
7. mutation checks
8. dogfood checks
9. performance checks
10. final artifact audit
```

Not every task requires every stage. Required stages are determined by task type and complexity.

## Stage Requirements

| Stage | Required evidence | Blocks on |
| --- | --- | --- |
| Task-system validation | `python3 scripts/validate_task_system.py` output. | Any queue/status/schema/task file mismatch. |
| Targeted unit tests | Command and pass/fail summary for changed behavior. | Compile failure or assertion failure. |
| Broader unit tests | Phase-appropriate full suite. | Any deterministic failure. |
| Property tests | Seed list, invariant list, generated case count. | Missing seed, nondeterministic output, invariant failure. |
| Doctests | Case IDs, changed docs, normalized output or snapshot diff. | Invalid block, stale output, nondeterministic case order. |
| Snapshot verification | Semantic diff summary for changed snapshots. | Unreviewed snapshot update. |
| Mutation checks | Baseline evidence, mutation report, survivor triage. | Invalid mutants, baseline failure, untriaged survivors. |
| Dogfood checks | Scope, config, report path, runtime budget. | Internal zentinel error, nondeterministic report, protected survivor increase. |
| Performance checks | Benchmark or smoke result with normalized durations. | Budget regression for performance-sensitive tasks. |
| Final artifact audit | Required handoff paths and status update. | Missing handoff, stale context, inconsistent state. |

The task-system validator also checks governance bootstrap files, ADR index consistency, and docs-to-tests gap registry coverage rows.

## Fail-Fast Rules

- Stop immediately on task-system validation failure.
- Stop on compile failure before mutation checks.
- Stop on baseline test failure before mutation checks.
- Stop on invalid mutant unless task explicitly investigates invalid mutants.
- Continue through survivor triage when survivors are expected review artifacts.

## Reports

Verifier emits:

```text
artifacts/pipeline/<task-id>/verification/report.md
artifacts/pipeline/<task-id>/verification/report.json
```

Report must include:

- commands executed
- pass/fail status
- required stages skipped with reasons
- artifact references
- residual risk
- final recommendation

JSON report shape:

```json
{
  "schema_version": "zentinel.pipeline.verification.v1",
  "task_id": "046",
  "status": "passed",
  "stages": [
    {
      "name": "task_system_validation",
      "required": true,
      "status": "passed",
      "command": "python3 scripts/validate_task_system.py",
      "artifact": "artifacts/pipeline/046/verification/task-system.txt"
    },
    {
      "name": "mutation_checks",
      "required": false,
      "status": "not_applicable",
      "reason": "documentation-only task"
    }
  ],
  "residual_risk": [],
  "recommendation": "complete"
}
```

Allowed stage statuses:

```text
passed
failed
blocked
not_applicable
skipped_by_policy
```

`skipped_by_policy` requires a policy citation. `not_applicable` requires a task-scope reason.

## CI Integration

CI should run the same stages available for the current phase:

- task-system validation
- Zig tests
- property tests when implemented
- doctests when implemented
- mutation fixture dogfood when implemented
- performance smoke checks when implemented

CI must not require remote AI providers.

## Completion Decision

The Verifier may recommend `complete` only when:

- all required stages passed
- all skipped stages have policy-backed reasons
- every prior role handoff is present
- no stale context artifacts remain unresolved
- queue/status files are ready for the next task

Any other outcome is `blocked`, `return_to_role`, or `create_follow_up_task`.
