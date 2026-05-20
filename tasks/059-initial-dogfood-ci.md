# 059 Initial Dogfood CI

Sequential guard: start this task only after task 058 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Run initial advisory dogfood over selected production-source modules and document the first CI integration. This task is not the final release dogfood gate.

## Scope

- Configure initial advisory dogfood over selected internal modules.
- Archive dogfood reports and compare repeated output.
- Wire and document the in-repository `scripts/ci.sh` CI entrypoint and artifact retention.
- Keep survivor changes reviewed rather than score-driven.
- Leave final release dogfood gating to task `085` after doctest mutation, property infrastructure, pipeline artifact CI, recovery validation, public-doc doctests, and doctest survivor AI are complete.

## Files allowed to modify

- `zentinel.dogfood.toml`
- `build.zig`
- `scripts/**`
- `docs/CI_STRATEGY.md`
- `docs/DOGFOODING.md`
- `test/dogfood_production_test.zig`
- `test/fixtures/dogfood/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add a failing initial advisory dogfood smoke test or report comparison before wiring CI docs.
- Add a failing `scripts/ci.sh` smoke or documentation check proving the canonical CI entrypoint runs the required deterministic stages.
- Run fixture and selected production dogfood commands.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Selected initial production-source dogfood runs deterministically.
- Dogfood JSON reports are archived or referenced by stable paths.
- `scripts/ci.sh` is the canonical in-repository CI entrypoint for required deterministic checks.
- CI strategy documents required dogfood stages and artifact retention.
- No invalid mutants appear in protected scope.
- The task status explicitly records that task `059` is not the final release dogfood gate and names task `085` as the final gate.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Final release dogfood gate or release acceptance sign-off.
- Experimental backend dogfood by default.
- Remote AI provider requirements.
- Hosted CI provider workflow files such as `.github/workflows/*.yml`.

## Suggested implementation approach

1. Start with small internal modules.
2. Normalize reports for repeat comparison.
3. Document survivor triage thresholds.
4. Keep default CI network-independent.

## Dogfooding implications

This is the Phase 7 initial advisory dogfood expansion. Final release dogfood gating is deferred to task `085`.

## Follow-up tasks

- `tasks/061-doctest-mutate-stabilization.md`
