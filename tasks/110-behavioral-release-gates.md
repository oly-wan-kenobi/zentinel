# 110 Make Release Gates Verify Behavior

Sequential guard: start this task only after task `109` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (High, test-quality). release_dogfood_gate.py / release_acceptance.py validate file-existence and self-authored manifest booleans (e.g. `normalized_equal:true`, substring command checks); they accept fabricated evidence and never run the binary.

## Goal

Make the release and dogfood gates verify real behavior: produce dogfood evidence from an actual `zentinel run`, recompute the repeated-run comparison instead of trusting a manifest boolean, and execute (not merely name) the `verified_by` checks.

## Scope

- Replace the dogfood `normalized_equal` boolean trust with a real recomputation over archived reports.
- Replace `verified_by` string-presence with actually invoking the referenced check, or remove the claim.
- Regenerate artifacts/pipeline/085/dogfood/run1|run2 from a real run (real hash IDs, real config_hash, real project_root).

## Files allowed to modify

- `scripts/release_dogfood_gate.py`
- `scripts/release_acceptance.py`
- `scripts/dogfood-production.sh`
- `test/fixtures/release/**`
- `test/fixtures/dogfood/**`
- `artifacts/pipeline/085/dogfood/**`
- `artifacts/pipeline/110/**`
- `docs/DOGFOODING.md`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing self-test that a fabricated manifest (bogus `verified_by` paths, `normalized_equal:true` with non-equal reports, survivor 'resolved' by an arbitrary string) is REJECTED by the gate. Current gate passes it; the test must fail until the gate recomputes.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- The dogfood gate recomputes the normalized comparison from the archived reports rather than reading a manifest boolean.
- A manifest asserting determinism while its referenced reports are not normalized-equal is rejected.
- `verified_by` checks are executed (or their claims removed); fabricated evidence no longer passes.

## Non-goals

- Changing what counts as release-acceptance criteria.
- Adding hosted-CI workflow files.

## Suggested implementation approach

1. Add a fabricated-manifest fixture under test/fixtures/release/invalid and assert rejection.
2. Recompute determinism from run_a/run_b; invoke the verified_by scripts/tests.
3. Regenerate the 085 dogfood archives from a real run (depends on task 108).

## Dogfooding implications

zentinel's release gate proves the product works rather than that committed files exist.

## Follow-up tasks

- None predefined.
