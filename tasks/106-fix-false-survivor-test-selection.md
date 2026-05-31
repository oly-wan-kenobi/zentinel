# 106 Fix False-Survivor Test Selection

Sequential guard: start this task only after task `060` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (High, correctness). The default `same_file_then_package` strategy (src/test_selection.zig:57) rewrites the configured `zig build test` into a weaker `zig test <file>`, so a mutant the configured suite KILLS is reported `survived`.

## Goal

Guarantee the default test-selection strategy never reports a mutant as `survived` when the user's configured command set would kill it. A narrowed same-file selection must either be proven a superset of the configured killers or have its surviving mutants re-verified against the configured commands before classification.

## Scope

- Make `same_file_then_package` sound: a `survived` verdict from a narrowed selection is re-verified against the configured command set before it is recorded as `survived`.
- Record in the report when a survivor was confirmed against the configured suite vs. only the selected subset.
- Document the soundness guarantee in docs/TEST_SELECTION.md.

## Files allowed to modify

- `src/test_selection.zig`
- `src/run_command.zig`
- `src/report.zig`
- `docs/TEST_SELECTION.md`
- `test/test_selection_test.zig`
- `test/fixtures/test_selection/**`
- `artifacts/pipeline/106/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test reproducing the audit repro: a file whose mutated function is covered only by a sibling `*_test.zig`, where `zig build test` kills the mutant but `zig test <file>` does not; assert zentinel does NOT report it `survived` under the default strategy.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- A mutant killed by the configured command set is never reported `survived` due to same-file selection.
- Survivors from a narrowed selection are re-run against the configured command set (or selection conservatively falls back to it) before the report records `survived`.
- docs/TEST_SELECTION.md states the soundness guarantee and the re-verification behavior.

## Non-goals

- New selection strategies beyond making the default sound.
- Changing configured-command semantics.

## Suggested implementation approach

1. Reproduce the false survivor as a failing fixture + test.
2. On a same-file `survived`, escalate to the configured commands before recording the verdict; only keep `survived` if the configured suite also fails to kill it.
3. Surface the verification scope in the report and document it.

## Dogfooding implications

zentinel's own survivor counts and mutation score become trustworthy under the shipped default strategy.

## Follow-up tasks

- None predefined.
