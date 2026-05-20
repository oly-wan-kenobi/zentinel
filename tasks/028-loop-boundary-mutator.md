# 028 Loop Boundary Mutator

Sequential guard: start this task only after task 027 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement the stable `loop_boundary` mutator for loop termination and range expressions.

## Scope

- Mutate loop comparison boundaries and syntactically safe range ends.
- Add fixtures for zero, one, many, and exact-end iteration.
- Keep infinite-loop and non-integer range contexts out of scope.

## Files allowed to modify

- `src/mutators/loop_boundary.zig`
- `src/ast_backend.zig`
- `src/mutant.zig`
- `test/mutators/loop_boundary_test.zig`
- `test/fixtures/mutators/loop_boundary/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/integer_boundary.zig`
- `src/mutators/allocator.zig`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add a failing test for `while` comparison boundary mutation.
- Add a failing test for range end `+1` or `-1` mutation where syntactically safe.
- Add a failing test that unsafe infinite-loop contexts are skipped or rejected deterministically.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `loop_boundary` follows `docs/MUTATOR_SPEC.md`.
- Mutants remain one patch at a time.
- Candidate ordering is stable across repeated collection.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- General integer literal mutation owned by task 027.
- Safety-mode matrix behavior.
- ZIR/AIR backend support.

## Suggested implementation approach

1. Reuse comparison-boundary handling where possible.
2. Treat range-end mutation as a separate operator candidate shape.
3. Add explicit fixtures before recognizer changes.
4. Avoid broad AST backend refactors.

## Dogfooding implications

Loop fixtures prepare Phase 2 semantic dogfood for iteration-heavy code.

## Follow-up tasks

- `tasks/029-phase2-semantic-dogfood.md`
