# 009 AST Candidate Ordering

Sequential guard: start this task only after task 008 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement deterministic candidate collection and sorting for AST backend candidates without enabling specific mutation operators.

## Scope

- Define candidate collector interfaces.
- Sort candidates according to `docs/MUTATOR_SPEC.md`.
- Deduplicate identical candidates.
- Add fixtures proving order stability.

## Files allowed to modify

- `src/ast_backend.zig`
- `src/mutant.zig`
- `test/ast_candidate_ordering_test.zig`
- `test/fixtures/candidate_ordering/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/runner.zig`
- `src/sandbox.zig`
- `src/cli.zig`
- `src/ai/**`

## Required tests

- Add a failing test for canonical ordering by file, span, operator, replacement, backend.
- Add a failing duplicate-candidate test.
- Add a failing test that order is stable across repeated collection.
- Run `zig build test`.

## Acceptance criteria

- Candidate ordering matches the spec exactly.
- Duplicate candidates are removed deterministically.
- Candidate collection can be called by future mutators.
- No tests are executed and no patches are applied.

## Non-goals

- Implementing actual Phase 1 mutators.
- Report rendering beyond test helper construction.
- Performance optimization.

## Suggested implementation approach

1. Create a small candidate builder used only by tests at first.
2. Sort using explicit comparator logic.
3. Keep dedupe keyed by durable identity fields.
4. Add tests before connecting real recognizers.

## Dogfooding implications

Stable ordering makes dogfood diffs reviewable and prevents worker scheduling from changing reports.

## Follow-up tasks

- `tasks/010-arithmetic-mutators.md`
