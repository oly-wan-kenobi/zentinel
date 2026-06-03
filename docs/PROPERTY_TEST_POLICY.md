# Property Test Policy

Property tests verify invariants over generated or enumerated inputs. They complement unit tests and mutation tests.

## Required For

Property tests are required for:

- ID generation
- sorting and deterministic ordering
- cache key construction
- source span mapping
- parser/extractor behavior
- normalization and snapshot matching
- config normalization
- report summary derivation
- report rendering
- schedulers and work ordering
- mutation candidate deduplication

## Availability Cutover

Before task `044` refines this policy and task `062` implements generated property infrastructure, tasks that touch the required surfaces above must add deterministic property-style tests using the test mechanisms available in their allowed scope. Acceptable pre-infrastructure evidence includes enumerated unit tests, repeated-run tests, fixture cases, snapshots, or small table-driven checks that exercise the invariant without generated data.

Generated property-test infrastructure is mandatory only after task `062` is complete and only for tasks whose active scope requires generated coverage. After task `062`, generated property evidence must record the seed list, invariant list, and generated case count, then follow the seed, report, and review rules in this document unless a task explicitly records a narrower deterministic reason.

## Task Complexity Classes

Property-test requirements scale with the task complexity class:

| Task class | Property evidence |
| --- | --- |
| Low-risk | Not required unless the task touches a Required For surface. |
| Normal | Required when the task touches a Required For surface; enumerated or generated evidence is acceptable before task `062`. |
| High-risk | Required whenever a Required For surface is touched; a high-risk report with no property evidence is rejected. |
| Compiler-internal | Required; property evidence over source spans, ZIR mapping, or Zig-version internals is mandatory and missing evidence is an escalation trigger per `docs/PIPELINE_ESCALATION_POLICY.md`. |

A task whose active scope touches no Required For surface records `scope` `not_property_required` with a written reason instead of empty evidence.

## Mandatory Invariant Categories

| Category | Example |
| --- | --- |
| Determinism | Same input produces same output. |
| Stability | Reordering unrelated input does not affect canonical output. |
| Round-trip | Source offset maps to line/column and back where supported. |
| Isolation | Mutating sandbox output does not alter source input. |
| Monotonicity | Adding unrelated docs does not change existing doctest IDs. |
| Collision resistance | Distinct cache inputs produce distinct keys in tested samples. |

## Seed Policy

- Every randomized property test must use an explicit seed.
- Failing seed must be printed in test output.
- Default CI uses deterministic seed list.
- New seeds may be added by task, not generated silently.

## Review Expectations

Property Test Agent and Test Reviewer check:

- invariant relevance
- input domain coverage
- deterministic seed use
- meaningful shrinking or minimized failure examples
- no replacement of precise unit tests with weak properties

## Reports

The property-test report is written to `artifacts/pipeline/<task-id>/property/report.json`. Task `044` defines this contract and ships example artifacts; task `062` adds the deterministic seeded generator and the executable structural validator `src/property/report.zig` (exposed as `zentinel.property.report`), which is the enforced contract for report validity. The report shape is checked in Zig rather than by a registered JSON Schema file, so `zentinel.pipeline.property_report.v1` is intentionally absent from `docs/SCHEMA_REGISTRY.md`.

Each property entry records, at minimum:

- property name
- the mandatory invariant category it covers
- explicit seed list (never silently generated)
- generator summary, including generated case count
- shrinking status (`not_triggered`, `minimized`, or `unsupported`)
- result, with a minimized counterexample when the result is `failed`

```json
{
  "schema_version": "zentinel.pipeline.property_report.v1",
  "task_id": "044",
  "scope": "property_required",
  "task_class": "high_risk",
  "deterministic": true,
  "status": "passed",
  "properties": [
    {
      "name": "id_generation_determinism",
      "invariant": "Determinism",
      "seeds": [1, 2, 3],
      "generator": {
        "summary": "randomized mutant identity inputs over the canonical field tuple",
        "generated_cases": 256
      },
      "shrinking": { "status": "not_triggered" },
      "result": "passed",
      "counterexample": null
    }
  ]
}
```

Report rules:

- `status` is `failed` if and only if at least one property `result` is `failed`.
- A `failed` property must carry a minimized counterexample and `shrinking.status` `minimized` (or `unsupported` with a written reason).
- A `property_required` report for a high-risk or compiler-internal task must list at least one property; empty evidence is rejected.
- `invariant` must be one of the mandatory invariant categories above.
- Because `status` is derived from the property results, property ordering cannot change the report outcome, and the same seed must reproduce the same generated case sequence and failure report.
