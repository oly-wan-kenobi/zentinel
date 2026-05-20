# 023 Optional and Null Mutators

Sequential guard: start this task only after task 022 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement the first Phase 2 optional mutators: `optional_orelse_unreachable` and `optional_null_check`.

## Scope

- Generate `optional orelse fallback -> optional orelse unreachable`.
- Generate null equality swaps.
- Add fixtures for null-covered and null-missing behavior.
- Preserve compile expectation metadata.

## Files allowed to modify

- `src/mutators/optional.zig`
- `src/ast_backend.zig`
- `src/mutant.zig`
- `test/mutators/optional_test.zig`
- `test/fixtures/mutators/optional/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/error_path.zig`
- `src/mutators/allocator.zig`
- `src/ai/**`
- `src/cache.zig`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add failing tests for `orelse fallback -> orelse unreachable`.
- Add failing tests for `x == null`, `x != null`, `null == x`, and `null != x`.
- Add a failing fixture for an optional survivor caused by missing null-path tests.
- Run `zig build test`.

## Acceptance criteria

- Optional mutators match `docs/MUTATOR_SPEC.md`.
- Existing Phase 1 fixtures still pass.
- Compile expectations are correct for optional replacements.
- Reports include operator names without schema changes.

## Non-goals

- Optional default-value replacement.
- AIR/ZIR semantic optional mutation.
- AI null-path suggestions.

## Suggested implementation approach

1. Add AST fixtures before recognizer changes.
2. Keep null comparison handling operand-order aware.
3. Reuse comparison mutator infrastructure only where it does not blur operator names.
4. Add dogfood fixture coverage before enabling broadly.

## Dogfooding implications

Optional mutators are strong candidates for config parser dogfood once production-source dogfooding begins.

## Follow-up tasks

- `tasks/024-error-path-mutators.md`
