# 026 Errdefer Mutator

Sequential guard: start this task only after task 025 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement the stable `errdefer_remove` mutator after the backlog validation gate.

## Scope

- Generate `errdefer statement -> errdefer {}` candidates.
- Preserve deterministic source spans and candidate ordering.
- Add fixtures for cleanup-on-error and success-only paths.

## Files allowed to modify

- `src/mutators/error_path.zig`
- `src/ast_backend.zig`
- `src/mutant.zig`
- `test/mutators/errdefer_test.zig`
- `test/fixtures/mutators/errdefer/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/optional.zig`
- `src/mutators/allocator.zig`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add a failing test for `errdefer statement -> errdefer {}`.
- Add a failing test for declaration-only or scope-sensitive bodies being rejected or classified `may_fail`.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `errdefer_remove` candidates match `docs/MUTATOR_SPEC.md`.
- Existing `defer` behavior is not changed.
- Reports include stable operator metadata and compile expectation.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing `defer_remove` preview behavior.
- Allocator failure-path mutation.
- ZIR/AIR backend support.

## Suggested implementation approach

1. Reuse the error-path mutator module if it remains the narrowest owner.
2. Add fixture source before implementation.
3. Keep replacement text exactly `errdefer {}`.
4. Preserve one-mutant-per-patch semantics.

## Dogfooding implications

This extends Phase 2 semantic dogfood coverage for cleanup-on-error behavior.

## Follow-up tasks

- `tasks/027-integer-literal-boundary-mutator.md`
