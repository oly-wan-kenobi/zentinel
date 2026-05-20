# 059 Production Dogfood CI

Sequential guard: start this task only after task 058 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Run selected production-source dogfood and document CI gating.

## Scope

- Configure dogfood over selected internal modules.
- Archive dogfood reports and compare repeated output.
- Wire and document the in-repository `scripts/ci.sh` CI entrypoint and artifact retention.
- Keep survivor changes reviewed rather than score-driven.

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

- Add a failing production dogfood smoke test or report comparison before wiring CI docs.
- Add a failing `scripts/ci.sh` smoke or documentation check proving the canonical CI entrypoint runs the required deterministic stages.
- Run fixture and selected production dogfood commands.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Selected production-source dogfood runs deterministically.
- Dogfood JSON reports are archived or referenced by stable paths.
- `scripts/ci.sh` is the canonical in-repository CI entrypoint for required deterministic checks.
- CI strategy documents required dogfood stages and artifact retention.
- No invalid mutants appear in protected scope.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Release acceptance sign-off.
- Experimental backend dogfood by default.
- Remote AI provider requirements.
- Hosted CI provider workflow files such as `.github/workflows/*.yml`.

## Suggested implementation approach

1. Start with small internal modules.
2. Normalize reports for repeat comparison.
3. Document survivor triage thresholds.
4. Keep default CI network-independent.

## Dogfooding implications

This is the Phase 7 production dogfood expansion.

## Follow-up tasks

- `tasks/061-doctest-mutate-stabilization.md`
