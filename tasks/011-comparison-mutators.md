# 011 Comparison Mutators

Sequential guard: start this task only after task 010 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement AST candidates for equality and boundary comparison operators.

## Scope

- Generate `== <-> !=`.
- Generate `>= -> >`, `> -> >=`, `<= -> <`, and `< -> <=`.
- Preserve exact token spans and operator names.
- Add fixtures for boundary diagnostics.

## Files allowed to modify

- `src/mutators/comparison.zig`
- `src/ast_backend.zig`
- `src/mutant.zig`
- `test/mutators/comparison_test.zig`
- `test/fixtures/mutators/comparison/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/logical.zig`
- `src/mutators/boolean.zig`
- `src/runner.zig`
- `src/ai/**`

## Required tests

- Add failing tests for each equality and boundary transformation.
- Add a failing test for multiple comparisons sorted by source span.
- Add a failing test that comments and strings are not mutated.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- All comparison transformations match `docs/MUTATOR_SPEC.md`.
- Boundary operators use `comparison_boundary`.
- Equality operators use `equality_swap`.
- Candidate metadata includes equivalent-risk hints from the spec where supported by the model.

## Non-goals

- Semantic type checking.
- AI explanation.
- Test execution.

## Suggested implementation approach

1. Build table-driven operator mapping.
2. Reuse source span extraction from arithmetic mutators.
3. Add fixtures where missing exact-boundary tests would create survivors later.
4. Keep operator mapping data deterministic.

## Dogfooding implications

Comparison mutators will likely be high-value dogfood operators for config and selection code once execution exists.

## Follow-up tasks

- `tasks/012-logical-boolean-mutators.md`
