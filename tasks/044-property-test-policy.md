# 044 Property Test Policy

Sequential guard: Start this task only after task `043` is complete and `tasks/status.json` names `044` as the next queued task.

## Goal

Specify when property tests are required in the pipeline and how deterministic seeds, invariants, shrinking, and reports must work.

## Scope

- Refine `docs/PROPERTY_TEST_POLICY.md`.
- Define mandatory invariant categories for IDs, ordering, source spans, cache keys, schedulers, config normalization, and report rendering.
- Connect property-test requirements to task complexity classes.
- Add artifact examples for property-test reports.

## Files allowed to modify

- `docs/PROPERTY_TEST_POLICY.md`
- `docs/PIPELINE_ESCALATION_POLICY.md`
- `docs/VERIFICATION_PIPELINE.md`
- `docs/TDD_POLICY.md`
- `test/fixtures/pipeline/property_tests/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing policy fixture or validation example for a high-risk task missing required property-test evidence.
- Run `python3 scripts/validate_task_system.py`.
- If metadata validation exists, validate that property-test reports include seed, generator summary, invariant, and shrinking status.

## Required property tests

If property-test infrastructure exists, add one deterministic self-test proving the same seed produces the same generated case sequence and failure report.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. Example property-test reports must avoid timestamps and absolute paths.

## Mutation testing requirements

No mutation run is required unless property-test infrastructure code is changed. Once mutation testing exists, property-test validators must be mutation-tested for missing invariant and unstable seed branches.

## Acceptance criteria

- Task categories requiring property tests are explicit.
- Mandatory invariants are listed.
- Seed and shrinking rules are deterministic.
- Property-test report artifacts are specified.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not choose a property testing library.
- Do not implement generators.
- Do not modify runtime mutation behavior.

## Suggested implementation approach

1. Add a failing metadata example for missing seed or invariant fields.
2. Update the policy and verification docs together.
3. Cross-check escalation rules so compiler-internal tasks require property evidence.
4. Run validation and record evidence.

## Dogfooding implications

Property tests will become required for zentinel's own deterministic surfaces before dogfood gates can be trusted.

## Follow-up tasks

- `tasks/046-verification-pipeline.md`
- `tasks/062-property-generator-infrastructure.md`
