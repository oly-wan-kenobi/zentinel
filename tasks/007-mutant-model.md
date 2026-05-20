# 007 Mutant Model

Sequential guard: start this task only after task 006 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Define the shared `Mutant` model used by all backends and reports.

## Scope

- Add typed mutant IDs, source spans, operator names, backend names, and compile expectations.
- Implement deterministic ID hashing.
- Connect report structs to the shared model where appropriate.

## Files allowed to modify

- `src/mutant.zig`
- `src/report.zig`
- `test/mutant_model_test.zig`
- `test/snapshots/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ast_backend.zig`
- `src/runner.zig`
- `src/cli.zig`
- `src/ai/**`

## Required tests

- Add a failing test for deterministic ID generation from stable fields.
- Add a failing test that candidate ordering matches `docs/MUTATOR_SPEC.md`.
- Add a failing test for source span validation.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Same input fields always produce the same durable ID.
- Display ordering is independent of map or filesystem iteration.
- Compile expectation values are `compiles`, `may_fail`, and `must_fail`.
- Report serialization can consume the model without duplicating identity logic.

## Non-goals

- Generating candidates.
- Applying mutations.
- Running tests.

## Suggested implementation approach

1. Define model types before backend work starts.
2. Keep ID hashing independent of display index.
3. Validate spans against source length in pure tests.
4. Sort by file, byte span, operator, replacement, backend.

## Dogfooding implications

Stable mutant identity is central to dogfood triage. Any future change must preserve or explicitly migrate IDs.

## Follow-up tasks

- `tasks/008-ast-parser-spike.md`
