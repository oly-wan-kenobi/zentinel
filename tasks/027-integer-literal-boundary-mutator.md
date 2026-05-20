# 027 Integer Literal Boundary Mutator

Sequential guard: start this task only after task 026 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement the stable `integer_literal_boundary` mutator for boundary-like integer literals.

## Scope

- Generate deterministic `+1` and `-1` boundary candidates where local source mutation is meaningful.
- Reject protected literals such as version numbers, error codes, bit widths, and alignments by default.
- Add fixtures for zero, one, maximum-like values, and rejected contexts.

## Files allowed to modify

- `src/mutators/integer_boundary.zig`
- `src/ast_backend.zig`
- `src/mutant.zig`
- `test/mutators/integer_boundary_test.zig`
- `test/fixtures/mutators/integer_boundary/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/loop_boundary.zig`
- `src/mutators/allocator.zig`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add a failing test for integer boundary candidates in branch, range, slice, or length checks.
- Add a failing test proving protected literals are not mutated.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `integer_literal_boundary` follows `docs/MUTATOR_SPEC.md`.
- Candidate order is deterministic for paired `+1` and `-1` replacements.
- Compile expectations are recorded as `may_fail` where type range overflow is possible.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Loop range mutation owned by task 028.
- Comptime value boundary preview mutation.
- AI boundary suggestions.

## Suggested implementation approach

1. Start with syntax-local integer literals.
2. Classify protected contexts through explicit rules.
3. Use fixture snapshots for candidate order.
4. Keep type inference out of scope unless already available.

## Dogfooding implications

Integer boundary fixtures become future dogfood targets for config and report code.

## Follow-up tasks

- `tasks/028-loop-boundary-mutator.md`
