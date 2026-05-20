# 045 Doctest Policy

Sequential guard: Start this task only after task `044` is complete and `tasks/status.json` names `045` as the next queued task.

## Goal

Specify how doctests participate in the AI-agent pipeline and when executable documentation becomes mandatory for public zentinel behavior.

## Scope

- Refine `docs/DOCTEST_POLICY.md`.
- Connect doctest requirements to `docs/DOCTEST_SPEC.md`, `docs/DOCTEST_BLOCK_FORMATS.md`, and `docs/VERIFICATION_PIPELINE.md`.
- Define public docs that require executable examples after doctest support exists.
- Define snapshot and mutation-aware doctest handoff requirements.

## Files allowed to modify

- `docs/DOCTEST_POLICY.md`
- `docs/DOCTEST_SPEC.md`
- `docs/DOCTEST_BLOCK_FORMATS.md`
- `docs/VERIFICATION_PIPELINE.md`
- `docs/AGENT_GUIDE.md`
- `test/fixtures/pipeline/doctest_policy/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add a failing policy fixture or validation example for a public CLI doc change missing doctest evidence.
- Run `python3 scripts/validate_task_system.py`.
- If doctest metadata validation exists, validate compile-pass, compile-fail, CLI, JSON expected, config, and snapshot case requirements.

## Required property tests

If doctest extraction code exists, add a property-style test proving deterministic case IDs and extraction order for repeated runs over the same Markdown.

## Required doctests

No self-hosted executable doctests are required until `zentinel doctest` exists. Any examples added by this task must use supported block formats and normalization rules.

## Mutation testing requirements

No mutation run is required unless doctest implementation code is changed. Once `zentinel doctest --mutate` exists, policy examples for mutator docs must be mutation-aware.

## Acceptance criteria

- Doctest mandatory stages are clear.
- Public docs requiring doctests are listed.
- Snapshot update rules are explicit.
- Doctest results feed the final verifier report.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not implement doctest parsing or execution.
- Do not rewrite all public docs.
- Do not enable mutation-aware doctests.

## Suggested implementation approach

1. Add a failing example for missing doctest evidence on a public doc change.
2. Update doctest policy and cross-links.
3. Check the verification pipeline order includes doctests before mutation-aware documentation checks.
4. Record validation output.

## Dogfooding implications

This task defines when zentinel's own CLI, config, report, mutator, and AI docs become executable contracts.

## Follow-up tasks

- `tasks/046-verification-pipeline.md`
- `tasks/066-public-docs-doctest-coverage.md`
