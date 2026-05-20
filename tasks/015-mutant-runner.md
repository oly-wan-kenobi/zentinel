# 015 Mutant Runner

Sequential guard: start this task only after task 014 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Run selected test commands against one patched mutant sandbox and classify the mutant result.

## Scope

- Combine mutant model, sandbox, and runner.
- Classify killed, survived, compile_error, compiler_crash, timeout, and invalid.
- Record command evidence.
- Keep execution serial for now.

## Files allowed to modify

- `src/mutant_runner.zig`
- `src/runner.zig`
- `src/sandbox.zig`
- `src/report.zig`
- `test/mutant_runner_test.zig`
- `test/fixtures/mutant_runner/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/worker_pool.zig`
- `src/cache.zig`
- `src/ai/**`
- `src/mutators/**`

## Required tests

- Add failing tests for killed, survived, compile_error, compiler_crash, timeout, and invalid patch cases.
- Add a failing test proving abnormal Zig compiler termination is classified as `compiler_crash`, not `compile_error`, `invalid`, or `internal_error`.
- Add a failing test that fail-fast per mutant records skipped commands.
- Add a failing test that mutant results preserve the structured command evidence emitted by the runner without falling back to a display-only command string.
- Run `zig build test`.

## Acceptance criteria

- Mutant result classification follows `docs/REPORT_FORMAT.md`.
- Compile errors are not treated as internal invalid mutants.
- Compiler crashes are not treated as compile errors, invalid mutants, or zentinel internal errors.
- Invalid patches are distinguished from Zig compile failures.
- Serial execution produces deterministic structured command evidence.

## Non-goals

- CLI `run` orchestration.
- Parallel execution.
- Cache reuse.
- AI explanation.

## Suggested implementation approach

1. Implement classification as a pure function over command results.
2. Use sandbox tests to provide patched fixture workspaces.
3. Keep process evidence bounded for reports.
4. Add integration tests only after pure classification passes.

## Dogfooding implications

This task provides the core execution behavior required for Stage 1 fixture dogfooding.

## Follow-up tasks

- `tasks/016-minimal-run-command.md`
