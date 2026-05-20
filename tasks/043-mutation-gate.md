# 043 Mutation Gate

Sequential guard: Start this task only after task `042` is complete and `tasks/status.json` names `043` as the next queued task.

## Goal

Define the pipeline mutation gate that runs after implementation review and before final verification for mutation-testable tasks.

## Scope

- Refine `docs/MUTATION_GATE_POLICY.md`.
- Connect mutation gate outcomes to `docs/VERIFICATION_PIPELINE.md` and `docs/FAILURE_RECOVERY.md`.
- Define survivor classification, equivalent-risk handling, retry behavior, and escalation rules.
- Add artifact examples for mutation gate reports.

## Files allowed to modify

- `docs/MUTATION_GATE_POLICY.md`
- `docs/VERIFICATION_PIPELINE.md`
- `docs/FAILURE_RECOVERY.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/DOGFOODING.md`
- `test/fixtures/pipeline/mutation_gate/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing fixture or contract example for an untriaged survivor before updating the policy.
- Run `python3 scripts/validate_task_system.py`.
- If report validation exists, validate mutation gate artifacts for killed, survived, compile_error, compiler_crash, timeout, and invalid cases.

## Required property tests

If mutation gate validation code exists, add property-style tests proving survivor ordering and classification output remain stable under input ordering changes.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. Policy examples that show command output must use future-compatible doctest block tags.

## Mutation testing requirements

This task defines mutation testing requirements but does not run product mutation checks. If validation code is touched, run mutation checks against the mutation gate classifier once available.

## Acceptance criteria

- The gate position is exactly `Tests -> Implementation -> Review -> Mutation Gate -> Survivor Triage -> Final Verification`.
- Blocking conditions are explicit.
- Equivalent mutant handling is advisory unless backed by deterministic policy.
- Retry limits and escalation paths are documented.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not implement mutation execution.
- Do not add survivor scoring thresholds.
- Do not allow AI to waive survivors.

## Suggested implementation approach

1. Add a failing artifact fixture for a survivor without triage.
2. Update policy docs and artifact examples.
3. Verify that failure recovery references the same statuses and retry limits.
4. Record validation output in task status.

## Dogfooding implications

This gate becomes mandatory for future zentinel dogfood tasks that change mutators, source mapping, runner behavior, or test selection.

## Follow-up tasks

- `046-verification-pipeline.md`
- `048-failure-recovery.md`
