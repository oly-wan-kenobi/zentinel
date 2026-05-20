# 055 AI Doctest Assistance

Sequential guard: start this task only after task 054 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Add advisory-only AI assistance for doctest failures, snapshots, and missing executable examples.

## Scope

- Build doctest AI context and schema targets.
- Expose `zentinel doctest explain <case-ref>` and `zentinel doctest suggest <doc-path>` as user-facing CLI subcommands.
- Suggest missing examples and snapshot-review summaries.
- Label doctest AI output as advisory-only.
- Keep normal doctest pass/fail deterministic.

## Files allowed to modify

- `src/ai/**`
- `src/cli.zig`
- `src/doctest/**`
- `src/main.zig`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `schemas/ai.doctest.context.v1.schema.json`
- `schemas/ai.doctest.suggest.response.v1.schema.json`
- `schemas/ai.doctest.snapshot_review.response.v1.schema.json`
- `test/ai_doctest_cli_test.zig`
- `test/ai_doctest_test.zig`
- `test/fixtures/ai/doctest/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add a failing doctest AI context schema or snapshot test.
- Add failing schema-validation tests for doctest explanation, suggestion, and snapshot-review response payloads. Doctest explanation responses reuse `schemas/ai.explain.response.v1.schema.json` and must use its doctest-specific classification labels.
- Add a failing test that AI suggestions cannot update expected output automatically.
- Add a failing stub-provider doctest assistance test.
- Add failing CLI tests for `zentinel doctest explain <case-ref>` with a selected report, the default report path, missing reports using `ZNTL_AI_REPORT_NOT_FOUND`, unknown case refs using `ZNTL_DOCTEST_CASE_NOT_FOUND`, durable `dt_...` IDs, and source-ref selectors.
- Add failing CLI tests for `zentinel doctest suggest <doc-path>` with the stub provider, no report present, optional `--report` context, invalid docs paths using `ZNTL_DOCTEST_DOC_NOT_FOUND`, and proof that suggestions do not edit docs.
- Add failing CLI tests for doctest AI `--ai-provider <disabled|stub|local|remote>` behavior consistent with `docs/CLI_SPEC.md`, including `ZNTL_AI_PROVIDER_NOT_ALLOWED` for disallowed remote providers.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Doctest AI context is privacy-filtered and deterministic.
- Doctest AI subcommands are usable from the CLI and documented in `docs/CLI_SPEC.md`.
- AI suggestions are stored separately from doctest results.
- Malformed AI output cannot alter doctest pass/fail.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Remote provider tests in the default suite.
- Mutation-aware doctest stabilization.
- Changing mutator docs.

## Suggested implementation approach

1. Reuse AI provider plumbing.
2. Reuse the AI command option parser for `--ai-provider` and `--report`.
3. Keep durable doctest case IDs as evidence refs and treat source refs as selectors only.
4. Snapshot normalized advisory output.
5. Fail closed on privacy or schema errors.

## Dogfooding implications

Doctest AI artifacts help future agents review executable docs without becoming correctness oracles.

## Follow-up tasks

- `tasks/056-zir-backend-experiment.md`
