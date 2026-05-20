# 010 Arithmetic Mutators

Sequential guard: start this task only after task 019 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement AST candidates for `arithmetic_add_sub` and `arithmetic_mul_div`.

## Scope

- Generate `+ <-> -` and `* <-> /` binary-expression mutants.
- Preserve exact token spans.
- Mark compile expectation as documented in `docs/MUTATOR_SPEC.md`.
- Add fixtures for killed, survived, and compile-error-risk cases.

## Files allowed to modify

- `src/ast_backend.zig`
- `src/mutators/arithmetic.zig`
- `src/mutant.zig`
- `test/mutators/arithmetic_test.zig`
- `test/fixtures/mutators/arithmetic/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/comparison.zig`
- `src/mutators/logical.zig`
- `src/mutators/boolean.zig`
- `src/runner.zig`
- `src/sandbox.zig`
- `src/ai/**`

## Required tests

- Add failing fixture tests for `+ -> -`, `- -> +`, `* -> /`, and `/ -> *`.
- Add a failing test that unary minus is not mutated.
- Add a failing test for deterministic candidate ordering when multiple arithmetic operators exist.
- Run `zig build test`.

## Acceptance criteria

- Arithmetic candidates match the exact before/after transformations in `MUTATOR_SPEC.md`.
- Unary operators and unsupported operators are ignored.
- Expected compile metadata is populated.
- No mutants are executed yet.

## Non-goals

- Applying patches.
- Classifying killed/survived.
- Mutating wrapping or saturating arithmetic.

## Suggested implementation approach

1. Add recognizer tests with source snippets before implementation.
2. Use the AST parser adapter from task 008.
3. Keep mutator logic in a dedicated module.
4. Return candidates through the shared collector from task 009.

## Dogfooding implications

Arithmetic mutators are basic signal tests for future dogfood runs but should not be used on zentinel core until runner and reports exist.

## Follow-up tasks

- `tasks/011-comparison-mutators.md`
