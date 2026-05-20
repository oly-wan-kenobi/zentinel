# 017 List Mutants Command

Sequential guard: start this task only after task 016 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement `zentinel list-mutants` to generate and display candidate mutants without running tests.

## Scope

- Load and validate config.
- Generate candidates through the stable AST backend.
- Render text and JSON candidate lists.
- Support filtering by operator when documented.

## Files allowed to modify

- `src/cli.zig`
- `src/main.zig`
- `src/list_mutants_command.zig`
- `src/ast_backend.zig`
- `src/report.zig`
- `test/list_mutants_command_test.zig`
- `test/snapshots/list_mutants_*.txt`
- `test/snapshots/list_mutants_*.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/runner.zig`
- `src/sandbox.zig`
- `src/ai/**`
- `src/cache.zig`
- `src/mutators/optional.zig`

## Required tests

- Add a failing snapshot for text output.
- Add a failing snapshot for JSON output.
- Add a failing test for operator filtering.
- Add a failing test that no test command is executed.
- Run `zig build test`.

## Acceptance criteria

- Candidate listing is deterministic.
- JSON output uses shared mutant fields where applicable.
- Experimental backends are rejected unless explicitly enabled by existing config rules.
- The command performs no patching and no test execution.

## Non-goals

- Running mutants.
- AI explanations.
- Performance scheduling.

## Suggested implementation approach

1. Reuse AST candidate generation from `run`.
2. Add a renderer focused on candidate metadata.
3. Keep command output stable through snapshots.
4. Make filtering pure and tested.

## Dogfooding implications

Candidate listing helps review zentinel's future self-mutation scope before execution.

## Follow-up tasks

- `tasks/018-report-renderers.md`
