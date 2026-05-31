# 113 Wire The Mutation-Aware Doctest Survivor Path

Sequential guard: start this task only after task `112` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (Medium, dead-code). `doctest explain-survivor` (src/cli.zig:925) reads ds_/status=survived from a report no command produces; `stableMutationRun` (the only producer) is test-only and `doctest --mutate` is fenced to fixtures and writes stdout only.

## Goal

Make `zentinel doctest explain-survivor` reachable end-to-end, or mark it unimplemented. Preferably wire `stableMutationRun` into a config-gated `doctest --mutate` that persists a mutation-aware report to the survivor path the AI command reads.

## Scope

- Either route `doctest --mutate` through `stableMutationRun` and persist its report to the default survivor report path, or document the command as not-yet-functional in CLI_SPEC.
- Remove the hardcoded fixtures-only path gate in favor of config opt-in (if wiring).

## Files allowed to modify

- `src/cli.zig`
- `src/doctest/mutation_experiment.zig`
- `src/ai/doctest_command.zig`
- `docs/CLI_SPEC.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `test/ai_doctest_survivor_cli_test.zig`
- `test/fixtures/doctest/**`
- `artifacts/pipeline/113/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/report.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing end-to-end test: run the mutation-aware doctest path to produce a report, then `doctest explain-survivor <ds_...>` resolves a real survivor (currently always ZNTL_DOCTEST_SURVIVOR_NOT_FOUND).
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `doctest explain-survivor` resolves a survivor from a report the tool can actually produce, or CLI_SPEC marks it unimplemented and the subcommand errors accordingly.
- No advertised CLI subcommand dead-ends with no possible input.

## Non-goals

- Designing new doctest mutation operators.
- AI changing any doctest status (advisory-only invariant preserved).

## Suggested implementation approach

1. Wire stableMutationRun into runDoctestMutate with persisted output behind a config opt-in.
2. Replace the fixtures-substring gate; add the end-to-end test.

## Dogfooding implications

zentinel's doctest survivor assistance works on its own docs, not only on a test-only code path.

## Follow-up tasks

- None predefined.
