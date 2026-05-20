# 004 Fixture System

Sequential guard: start this task only after task 003 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Create the fixture layout and loader used by future mutation tests.

## Scope

- Add `test/fixtures` structure.
- Define fixture metadata.
- Add a minimal fixture project that can be compiled by Zig.
- Add loader tests that do not generate mutants yet.

## Files allowed to modify

- `test/fixtures/**`
- `test/support/fixture.zig`
- `test/fixture_system_test.zig`
- `build.zig`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ast_backend.zig`
- `src/runner.zig`
- `src/ai/**`

## Required tests

- Add a failing fixture loader test.
- Add a failing test that validates fixture metadata.
- Add a failing test that confirms fixture paths normalize project-relative paths.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Fixture loader can enumerate fixture projects deterministically.
- Fixture metadata names target files, expected operators, and expected outcomes.
- The minimal fixture compiles through a test command.
- No mutant generation is implemented.

## Non-goals

- Applying patches.
- Running mutants.
- Implementing mutators.

## Suggested implementation approach

1. Define a small metadata format such as JSON or TOML under each fixture.
2. Keep fixture source intentionally tiny.
3. Sort fixture discovery by normalized path.
4. Reuse test harness normalization helpers.

## Dogfooding implications

Fixture projects are Stage 1 dogfood inputs for the mutation engine.

## Follow-up tasks

- `tasks/005-version-policy.md`
