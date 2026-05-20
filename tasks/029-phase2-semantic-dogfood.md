# 029 Phase 2 Semantic Dogfood

Sequential guard: start this task only after task 028 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Run Phase 2 semantic fixture dogfood for stable Zig-native mutators.

## Scope

- Configure dogfood over Phase 2 semantic fixtures.
- Compare repeated reports for deterministic ordering.
- Record invalid mutants and survivor triage requirements.
- Keep production-source dogfood for later tasks.

## Files allowed to modify

- `zentinel.dogfood.toml`
- `build.zig`
- `scripts/**`
- `test/dogfood_semantic_test.zig`
- `test/fixtures/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `src/mutators/allocator.zig`

## Required tests

- Add a failing dogfood test or fixture expectation before wiring the command.
- Run the targeted semantic dogfood test.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Stable Phase 2 mutators run against fixture dogfood scope.
- Preview mutators are not implemented, enabled, or required by this dogfood task.
- Repeated fixture dogfood reports match after duration normalization.
- No invalid mutants appear in stable fixture scope.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Production-source dogfood.
- CI workflow creation.
- AI survivor triage.

## Suggested implementation approach

1. Use the existing dogfood fixture config if available.
2. Add semantic fixture selection incrementally.
3. Normalize durations and temp paths in report comparisons.
4. Capture follow-up tasks for any survivor triage gaps.

## Dogfooding implications

This is the first dogfood pass over Phase 2 semantic mutators.

## Follow-up tasks

- `tasks/030-doctest-conventions.md`
