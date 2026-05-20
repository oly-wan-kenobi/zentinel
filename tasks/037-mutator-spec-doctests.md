# 037 Mutator Spec Doctests

Sequential guard: start this task only after task 036 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Make mutator specification examples executable as before/after doctest contracts.

## Scope

- Convert stable mutator transformations in `docs/MUTATOR_SPEC.md` to `zig before` and `zig after` examples where practical.
- Validate before/after block extraction and pairing.
- Compare documented transformations against AST mutator output for stable Phase 1 operators.
- Report documentation drift when mutator output no longer matches docs.

## Files allowed to modify

- `docs/MUTATOR_SPEC.md`
- `src/doctest/**`
- `src/ast_backend.zig`
- `src/mutators/**`
- `test/doctest_mutator_spec_test.zig`
- `test/fixtures/doctest/mutator_spec/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/cache.zig`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add failing doctest tests for `arithmetic_add_sub`, `comparison_boundary`, and `boolean_literal` before/after pairs.
- Add a failing test for a before block without after block.
- Add a failing snapshot for transformation mismatch diagnostics.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Required property tests

- Before/after pair IDs are stable.
- Transformation matching is independent of unrelated prose.
- Candidate ordering remains canonical when a doc contains multiple before/after pairs.
- Mismatch diagnostics are deterministic.

## Acceptance criteria

- Stable mutator docs contain executable before/after examples.
- Doctest validation can detect documented transformation drift.
- Phase 1 mutator examples are checked against actual AST mutator output.
- No mutation execution against doctest assertions occurs yet.

## Non-goals

- `zentinel doctest --mutate`.
- Phase 2 mutator transformation coverage unless already stable.
- AI survivor explanations.
- Doctest cache.

## TDD instructions

Write failing before/after extraction and transformation tests first. Only then connect doctest validation to AST mutator generation for the smallest stable operator.

## Suggested implementation approach

1. Treat before/after validation as a deterministic doc contract.
2. Reuse existing mutator candidate generation without running tests.
3. Keep examples short enough to source-map clearly.
4. Do not infer transformations from prose.

## Dogfooding implications

Mutator specs begin acting as executable documentation for zentinel's core value proposition.

## Follow-up tasks

- `tasks/038-doctest-cache.md`
