# 024 Error Path Mutators

Sequential guard: start this task only after task 023 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement the first Phase 2 error-path mutator: `error_catch_unreachable`.

## Scope

- Generate `expr catch handler -> expr catch unreachable`.
- Add fixtures for handled error paths and success-only paths.
- Preserve exact catch handler source span.
- Report equivalent-risk metadata for untested error paths.

## Files allowed to modify

- `src/mutators/error_path.zig`
- `src/ast_backend.zig`
- `src/mutant.zig`
- `test/mutators/error_path_test.zig`
- `test/fixtures/mutators/error_path/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/optional.zig`
- `src/mutators/allocator.zig`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add a failing test for `catch handler -> catch unreachable`.
- Add a failing test that existing `catch unreachable` is not mutated.
- Add failing fixtures for killed and survived error-path behavior.
- Run `zig build test`.

## Acceptance criteria

- `error_catch_unreachable` candidates match `docs/MUTATOR_SPEC.md`.
- Existing Phase 1 and optional mutator tests still pass.
- Reports distinguish error-path survivors through operator metadata.
- No AI explanation is required for correctness.

## Non-goals

- Transforming `try`.
- Returning caught errors.
- Allocator failure injection.
- Experimental backend support.

## Suggested implementation approach

1. Add focused source snippets with `catch` forms.
2. Preserve handler replacement text exactly as `unreachable`.
3. Avoid mutating `catch unreachable`.
4. Add fixture outcomes after candidate tests pass.

## Dogfooding implications

Error-path mutators will later target zentinel runner and config diagnostics, where missing error tests are especially costly.

## Follow-up tasks

- `tasks/025-autonomous-backlog-audit.md`
- `tasks/026-errdefer-mutator.md`
