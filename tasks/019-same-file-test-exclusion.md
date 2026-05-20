# 019 Same-File Test Exclusion

Sequential guard: start this task only after task 009 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Ensure AST mutation generation excludes Zig `test` declaration bodies by default.

## Scope

- Identify `test` declarations in source traversal.
- Prevent candidates inside test bodies.
- Preserve candidates in production declarations in the same file.
- Record exclusion behavior in fixture metadata when useful.

## Files allowed to modify

- `src/ast_backend.zig`
- `src/source_map.zig`
- `test/same_file_test_exclusion_test.zig`
- `test/fixtures/same_file_tests/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/runner.zig`
- `src/test_selection.zig`
- `src/ai/**`

## Required tests

- Add a failing fixture with production code and same-file tests containing mutable operators.
- Add a failing test proving production candidates remain.
- Add a failing test proving test body candidates are excluded.
- Run `zig build test`.

## Acceptance criteria

- Operators inside `test` bodies are not emitted by default.
- Production code in the same file is still mutated.
- Exclusion is deterministic and covered by fixtures.
- No config option is added unless already documented.

## Non-goals

- Mutating tests as an explicit future mode.
- Test impact selection.
- AI test review.

## Suggested implementation approach

1. Add fixture before code changes.
2. Mark AST ranges corresponding to test declarations.
3. Filter candidates by source span overlap.
4. Keep exclusion separate from test selection.

## Dogfooding implications

This protects dogfood runs from mutating zentinel's own tests and misrepresenting production test strength.

## Follow-up tasks

- `tasks/010-arithmetic-mutators.md`
