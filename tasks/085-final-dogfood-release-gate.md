# 085 Final Dogfood Release Gate

Sequential guard: start this task only after task `067` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Run the final release dogfood gate after tasks `061`, `062`, `064`, `065`, `066`, and `067` have completed, so release acceptance verifies the hardened system rather than the initial advisory CI wiring.

## Scope

- Run fixture dogfood, selected internal module dogfood, public-doc doctest dogfood, and mutation-aware doctest dogfood required by the completed feature set.
- Compare deterministic repeated dogfood reports after normalizing observation metadata.
- Verify `scripts/ci.sh` includes the dogfood, artifact, recovery, public-doc doctest, and doctest survivor AI gates that exist by this point.
- Archive or reference final dogfood JSON reports under stable artifact paths.
- Record survivor, invalid-mutant, schema, recovery, and artifact validation evidence before release acceptance.

## Files allowed to modify

- `zentinel.dogfood.toml`
- `scripts/**`
- `docs/CI_STRATEGY.md`
- `docs/DOGFOODING.md`
- `docs/PROJECT_ACCEPTANCE_CRITERIA.md`
- `test/release_dogfood_gate_test.zig`
- `test/fixtures/dogfood/**`
- `test/fixtures/release/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing release dogfood gate test or fixture proving final dogfood cannot pass without archived deterministic dogfood evidence.
- Add a failing CI-script check proving `scripts/ci.sh` invokes the available final dogfood gates after tasks `061`, `062`, `064`, `065`, `066`, and `067`.
- Run fixture dogfood.
- Run selected internal module dogfood.
- Run public-doc doctest dogfood.
- Run mutation-aware doctest dogfood when task `061` support exists.
- Run doctest survivor AI stub-provider checks when task `067` support exists.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Final dogfood reports are generated, schema-valid, and stored or referenced by stable paths.
- Repeated final dogfood report comparison is deterministic after normalizing only documented observation metadata.
- Protected dogfood scope has no invalid mutants.
- Survivor changes in protected modules are either fixed by tests or recorded with deterministic equivalent-risk review evidence.
- Public docs doctest dogfood and mutation-aware doctest dogfood are included when their prerequisite tasks have landed.
- `scripts/ci.sh` exercises the final release dogfood gate before task `060` release acceptance.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing new mutators.
- Adding new AI provider modes.
- Changing release acceptance criteria outside dogfood evidence.
- Hosted CI provider workflow files such as `.github/workflows/*.yml`.

## Suggested implementation approach

1. Reuse the initial dogfood configuration from task `059`.
2. Add release-gate fixtures and CI-script assertions before changing `scripts/ci.sh`.
3. Run the dogfood commands twice and compare normalized reports.
4. Record final dogfood evidence in task status before release acceptance starts.

## Dogfooding implications

This task is the final release dogfood gate. It runs after the late hardening and advisory tasks so task `060` can verify release readiness from complete dogfood evidence.

## Follow-up tasks

- `tasks/060-release-acceptance-verification.md`
