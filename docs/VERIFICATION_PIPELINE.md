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
| Final artifact audit | Required handoff paths, active lock evidence, and status update. | Missing handoff, missing active lock, stale context, inconsistent state. |

The task-system validator also checks governance bootstrap files, ADR index consistency, and docs-to-tests gap registry coverage rows.

The Mutation checks stage runs the mutation gate defined in `docs/MUTATION_GATE_POLICY.md`. The gate report at `artifacts/pipeline/<task-id>/mutation/report.json` records a derived `gate_status`: a `passed` gate maps this stage to `passed`, and a `blocked` gate maps it to `failed` with the gate's `blocking_reasons` (baseline failure, invalid mutants present, nondeterministic mutation report, or an untriaged survivor). After task `043`, a mutation-testable task may not record this stage as skipped with `pre-gate unavailable`.

The Property tests stage follows `docs/PROPERTY_TEST_POLICY.md`. Evidence is recorded in `artifacts/pipeline/<task-id>/property/report.json` with each property's invariant category, explicit seed list, generator summary and case count, and shrinking status; the stage `status` is `failed` if any property fails. High-risk and compiler-internal tasks that touch a Required For surface must carry property evidence, and a missing seed or invariant blocks the stage.

The Doctests stage follows `docs/DOCTEST_POLICY.md`. Evidence is recorded in `artifacts/pipeline/<task-id>/doctest/report.json` with each case's kind, durable `dt_` id, `source_ref`, result, and snapshot status; the stage `status` mirrors the evidence `status` and is `failed` if any case fails or any snapshot mismatches. A task that changes a public CLI, config, report, or AI doc must cover each changed doc with at least one case, and an `updated` snapshot requires recorded Verifier approval.

## Fail-Fast Rules

- Stop immediately on task-system validation failure.
- Stop on compile failure before mutation checks.
- Stop on baseline test failure before mutation checks.
- Stop on invalid mutant unless task explicitly investigates invalid mutants.
- Continue through survivor triage when survivors are expected review artifacts.

## Reports

Task `041` is the cutover point for durable pipeline artifacts. Before task `041` is complete, the Verifier records the same report fields in `tasks/STATUS.md`, `tasks/status.json`, or the task completion summary. After task `041` is complete, the JSON report is the canonical durable artifact and the Markdown report is a companion summary.

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

JSON report shape (`schemas/pipeline.verification.v1.schema.json`, refined by task `046`):

```json
{
  "schema_version": "zentinel.pipeline.verification.v1",
  "task_id": "046",
  "status": "passed",
  "source_commit": "baseline",
  "working_tree_state": "clean",
  "active_lock": "artifacts/pipeline/046/locks/active-task-lock.json",
  "handoffs_present": ["artifacts/pipeline/046/handoffs/14-verifier.json"],
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
      "status": "skipped_by_policy",
      "policy": "docs/MUTATION_GATE_POLICY.md: not mutation-testable scope"
    },
    {
      "name": "final_artifact_audit",
      "required": true,
      "status": "passed",
      "evidence": "handoffs, active lock, and status updates consistent"
    }
  ],
  "residual_risk": [],
  "recommendation": "complete"
}
```

Per-stage required artifact fields:

- every stage records `name`, `required`, and `status`
- a required stage with `status` `passed` records the `command` it ran or an `evidence` summary
- a `not_applicable` stage records a task-scope `reason`
- a `skipped_by_policy` stage records a `policy` citation
- stage `name` values are unique within a record

Allowed stage statuses are `passed`, `failed`, `blocked`, `not_applicable`, and `skipped_by_policy`.

Derived outcome: `status` is `passed` only when every required stage is `passed`, `not_applicable`, or `skipped_by_policy`; it is `failed` if any required stage `failed`, otherwise `blocked` if any required stage is `blocked`. `recommendation` may be `complete` only when `status` is `passed`; otherwise it is `block`, `retry`, `escalate`, `return_to_role`, or `create_follow_up_task`. Because the outcome is derived from the stage set, stage ordering does not change the decision, and a record with duplicate stage names is rejected.

## CI Integration

The canonical CI entrypoint is `scripts/ci.sh` (see `docs/CI_STRATEGY.md`). CI runs the verification stages by invoking `scripts/ci.sh`; hosted provider workflow files are out of scope and external systems call that script rather than re-listing stages. CI runs the same stages available for the current phase:

- task-system validation
- pipeline artifact validation
- Zig tests
- property tests when implemented
- doctests when implemented
- mutation fixture dogfood when implemented
- performance smoke checks when implemented

After task `064`, `scripts/ci.sh` runs a dedicated `pipeline_artifact_validation` stage (`scripts/check_pipeline_artifacts.py`) that validates the committed `artifacts/pipeline/<task-id>/` tree — handoffs, the active lock, and context packets — against the baseline pipeline schemas with deterministic, project-relative diagnostics, and self-tests that check against `test/fixtures/pipeline/ci_artifacts/`. A schema or task-scope violation in any committed pipeline artifact blocks CI. See `docs/PIPELINE_ARTIFACTS.md` and `docs/CI_STRATEGY.md`.

Before task `062`, property evidence may be enumerated or fixture-based when generated property infrastructure does not exist. After task `062`, generated property evidence must include the seed list, invariant list, and generated case count. Task `062` ships the deterministic seeded generator (`zentinel.property.generator`) and the structural report validator (`zentinel.property.report`); the validator distinguishes passing property evidence from missing or malformed evidence and is the executable check behind this stage.

CI must not require remote AI providers.

## Completion Decision

The Verifier may recommend `complete` only when:

- all required stages passed
- all skipped stages have policy-backed reasons
- every prior role handoff is present, or before task `041`, equivalent pre-artifact handoff fields are present in task status or the completion summary
- after task `041`, the active lock artifact matches the task-control files and context packet
- no stale context artifacts remain unresolved
- queue/status files are ready for the next task

Any other outcome is `blocked`, `return_to_role`, or `create_follow_up_task`.
