# 067 AI Doctest Survivor Assistance

Sequential guard: start this task only after tasks `055`, `061`, and `066` are complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Expose advisory-only AI explanation for mutation-aware doctest survivors after stable doctest mutation report fields exist.

## Scope

- Expose `zentinel doctest explain-survivor <survivor-ref>` as a user-facing CLI subcommand.
- Build the `explain_doctest_survivor` doctest AI context from deterministic `zentinel doctest --mutate` report evidence.
- Reuse the shared advisory AI provider and prompt plumbing.
- Keep survivor status, mutation correctness, and equivalent-risk handling deterministic.

## Files allowed to modify

- `src/ai/**`
- `src/cli.zig`
- `src/doctest/**`
- `src/main.zig`
- `docs/CLI_SPEC.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `schemas/ai.prompt.v1.schema.json`
- `schemas/ai.doctest.context.v1.schema.json`
- `schemas/ai.explain.response.v1.schema.json`
- `test/ai_doctest_survivor_cli_test.zig`
- `test/fixtures/ai/doctest_survivor/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add failing CLI tests for `zentinel doctest explain-survivor <survivor-ref>` with an explicit mutation-aware doctest report and the default doctest report path.
- Add a failing CLI test for missing reports using `ZNTL_AI_REPORT_NOT_FOUND`.
- Add a failing CLI test for unresolved survivor refs using `ZNTL_DOCTEST_SURVIVOR_NOT_FOUND`.
- Add a failing schema-extension test proving `schemas/ai.doctest.context.v1.schema.json` adds `flow = "explain_doctest_survivor"` and evidence `kind = "doctest_survivor"` without weakening the task `055` non-survivor variants.
- Add a failing context schema fixture proving the flow is `explain_doctest_survivor`, evidence `kind` is `doctest_survivor`, and evidence includes `ds_...` survivor ref, selected case metadata, `m_...` mutant ID, mutated diff, operator, backend stability, and deterministic runner evidence copied from `case.mutation.runner_evidence`.
- Add a failing resolution test proving `<survivor-ref>` matches only non-null `case.mutation.survivor_ref` values in the selected mutation-aware doctest report and does not resolve killed, skipped, invalid, compile-error, compiler-crash, or timeout documentation mutants.
- Add a failing stub-provider output snapshot using doctest-specific classification labels from `zentinel.ai.explain.response.v1`.
- Add a failing test proving the command does not change survivor status, doctest report files, or expected output blocks.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `zentinel doctest explain-survivor <survivor-ref>` is documented and usable from the CLI.
- The command consumes only deterministic mutation-aware doctest report evidence from task `061`.
- The command resolves the `ds_...` survivor-ref format and derivation documented in `docs/DOCTEST_SPEC.md`.
- AI output is advisory-only and cannot mark survivors equivalent, killed, skipped, or invalid.
- Missing reports and unresolved survivor refs produce stable documented diagnostics.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Changing mutation-aware doctest report fields defined by task `061`.
- Implementing new mutators.
- Remote provider tests in the default suite.
- Automatic doctest edits, snapshot updates, or survivor suppression.

## Suggested implementation approach

1. Reuse the task `055` doctest AI command parser and provider plumbing.
2. Resolve survivor refs only against the selected mutation-aware doctest report.
3. Build the context packet from report evidence without re-running mutation.
4. Snapshot the stub provider output and the no-mutation side effects.

## Dogfooding implications

This task makes mutation-aware doctest survivors diagnosable by autonomous agents without making AI a correctness oracle.

## Follow-up tasks

None predefined.
