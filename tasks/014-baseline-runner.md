# 014 Baseline Runner

Sequential guard: start this task only after task 013 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement deterministic execution of baseline test commands before mutant execution.

## Scope

- Run configured test commands.
- Reuse the shared command parser from `src/command.zig` to turn configured command strings into argv according to `docs/CONFIG_SPEC.md`.
- Capture stdout, stderr, exit code, and timeout status.
- Record original command text, parsed argv, cwd, environment policy, and shell flag in command results.
- Classify baseline pass/fail, including the rule that baseline timeout maps to `run.status = baseline_failed` when report/run-command layers consume the result.
- Avoid mutation-specific behavior.

## Files allowed to modify

- `src/runner.zig`
- `src/command.zig`
- `src/config.zig`
- `test/runner_baseline_test.zig`
- `test/fixtures/runner/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutant_runner.zig`
- `src/ai/**`
- `src/ast_backend.zig`

## Required tests

- Add failing tests for passing command, failing command, timeout command, and captured output normalization.
- Add a failing classification test proving baseline timeout maps to `run.status = baseline_failed` semantics rather than an internal error or mutant timeout.
- Add a failing test that command order follows config order.
- Add a failing reuse/regression test proving runner execution uses the same parsed argv shape already validated by `zentinel check`.
- Keep command-parser coverage for quoted argv fields and rejected shell syntax in the shared parser tests from task 005; add runner-level regression coverage only if integration can drift.
- Add a failing test proving commands execute without an implicit shell and with the documented environment policy.
- Add a failing command-result snapshot proving baseline evidence includes original command text, parsed argv, cwd, environment policy, `shell = false`, phase, exit code, timeout flag, duration, and bounded excerpts.
- Run `zig build test`.

## Acceptance criteria

- Baseline runner classifies pass, fail, and timeout deterministically.
- Timeout is represented as deterministic baseline failure evidence for the report writer and run command.
- Configured command strings are executed as parsed argv, not through a shell.
- Command results expose the structured evidence required by `docs/REPORT_FORMAT.md` and `docs/SANDBOX_SECURITY.md`.
- Output excerpts are bounded and normalized for reports.
- Baseline failure prevents later mutation execution through a clear result path.
- Tests do not depend on live network or machine-specific commands.

## Non-goals

- Running mutants.
- Parallel workers.
- Cache.
- Test selection.

## Suggested implementation approach

1. Define a command execution abstraction for tests.
2. Implement pure classification separately from process spawning.
3. Reuse command-string parsing from `src/command.zig`; do not introduce runner-local parsing.
4. Keep timeout behavior injectable or simulated in unit tests.
5. Integrate real spawning only after classification and parser tests pass.

## Dogfooding implications

Baseline reliability is a dogfood prerequisite; zentinel must not mutate itself when its own tests are already failing.

## Follow-up tasks

- `tasks/015-mutant-runner.md`
