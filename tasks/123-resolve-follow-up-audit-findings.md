# 123 Resolve Follow-Up Audit Findings

Sequential guard: start this task only after task `122` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: the read-only multi-agent audit run after task `122`. The current actionable findings are symlink-blind scratch/report/config/AI paths, normal doctest `--file` containment drift, doctest AI redaction gaps, argv-unsafe generated same-file commands, backend parse errors without file context, cleanup warnings being swallowed, doctest report schema drift, invalid AST candidate diagnostics, snapshot self-blessing, and missing real-regression coverage for duplicate physical edits.

## Goal

Resolve every high, medium, and low finding from the post-122 audit and implement the recommended follow-up tasks while preserving deterministic core behavior, stable AST-default semantics, pinned Zig `0.16.0` support, and advisory-only AI boundaries.

## Scope

- Add shared project-root read/write containment helpers for lexical `..`/absolute paths plus symlinked path components, then apply them to mutation workspaces, doctest workspaces and scratch outputs, doctest mutation reports, config reads/writes, and AI report/doc reads.
- Make normal `zentinel doctest --file` reject out-of-root paths consistently with doctest mutation and AI doctest paths.
- Redact every doctest AI command-evidence field and skip reason before context construction.
- Replace generated same-file command execution with argv-safe structured handling and make generated preflight parse/construction failures visible in deterministic selection evidence.
- Preserve backend parse-error file context at CLI/report boundaries.
- Report sandbox cleanup failures instead of silently hiding them behind successful mutation results.
- Align `schemas/doctest.report.v1.schema.json` with the doctest command and run-error contracts.
- Surface invalid AST candidates as deterministic diagnostics or failures instead of silently dropping them, or align the contract if a stricter implementation is not viable.
- Remove snapshot self-blessing from normal test helpers.
- Add regression coverage for the historical real AST duplicate physical edit overlap, not only synthetic duplicate candidates.

## Files allowed to modify

- `src/config.zig`
- `src/root.zig`
- `src/cli.zig`
- `src/command.zig`
- `src/test_selection.zig`
- `src/run_command.zig`
- `src/list_mutants_command.zig`
- `src/ast_backend.zig`
- `src/mutant.zig`
- `src/mutant_runner.zig`
- `src/runner.zig`
- `src/ai/command.zig`
- `src/ai/context.zig`
- `src/ai/doctest_command.zig`
- `src/ai/redaction.zig`
- `src/doctest/report.zig`
- `src/doctest/workspace.zig`
- `schemas/doctest.report.v1.schema.json`
- `docs/CLI_SPEC.md`
- `docs/DOCTEST_SPEC.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/FAILURE_MODES.md`
- `docs/REPORT_FORMAT.md`
- `docs/SANDBOX_SECURITY.md`
- `docs/TEST_SELECTION.md`
- `docs/ZIG_VERSION_POLICY.md`
- `test/ai_command_test.zig`
- `test/ai_doctest_test.zig`
- `test/ai_doctest_cli_test.zig`
- `test/ai_doctest_survivor_cli_test.zig`
- `test/ast_candidate_ordering_test.zig`
- `test/cli_test.zig`
- `test/config_test.zig`
- `test/doctest_cli_command_test.zig`
- `test/doctest_mutate_stabilization_test.zig`
- `test/doctest_mutation_experiment_test.zig`
- `test/doctest_runner_test.zig`
- `test/list_mutants_command_test.zig`
- `test/mutant_runner_test.zig`
- `test/report_renderers_test.zig`
- `test/report_schema_test.zig`
- `test/run_command_test.zig`
- `test/sandbox_test.zig`
- `test/test_selection_test.zig`
- `test/zig_version_test.zig`
- `artifacts/pipeline/123/**`
- `tasks/123-resolve-follow-up-audit-findings.md`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `build.zig`
- `build.zig.zon`
- `.claude/**`

## Required tests

- Add failing tests before implementation for each behavior changed by this task. At minimum, cover symlink-safe read/write containment, normal doctest `--file` containment, doctest AI redaction of command evidence and skip reasons, argv-safe same-file generated commands, backend parse-error file context, cleanup warning visibility, doctest schema drift, invalid AST candidate diagnostics, snapshot missing-file failures, and real AST duplicate physical-edit overlap.
- Run targeted tests for changed modules.
- Run `zig build test`.
- Run `zig build`.
- Run `zig fmt --check src test`.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` while active and again after completion.

## Acceptance criteria

- No generated workspace, scratch file, mutation report, config write, config read, AI input read, or doctest documentation read can escape the project root through absolute paths, `..`, or in-root symlinks.
- Normal doctest, doctest mutation, mutation AI, doctest AI, survivor AI, config handling, and mutation/doctest workspace creation use consistent containment diagnostics and exit behavior.
- Doctest AI context redacts command originals, argv entries, cwd, and skip reasons according to the same privacy boundary as mutation AI.
- Same-file generated test commands execute using exact argv for valid project-relative file names, including spaces and command-parser metacharacter characters; when a generated command cannot be constructed, fallback evidence is visible and deterministic.
- Backend parse errors identify the offending project-relative file.
- Cleanup failures produce deterministic warning or diagnostic evidence and are not hidden behind successful mutation results.
- Doctest report schema, docs, and implementation agree on command evidence, `run.error.details`, shell usage, argv cardinality, and bounded error details.
- Invalid AST candidates cannot disappear silently; the behavior matches `docs/FAILURE_MODES.md` and `docs/INVARIANTS.md`.
- Snapshot tests fail when approved snapshots are missing instead of auto-writing them.
- Duplicate physical edits from the historical real AST overlap collapse to one deterministic representative.

## Non-goals

- Promoting ZIR or AIR from experimental status.
- Adding new stable mutators beyond tests needed to prove existing overlap behavior.
- Changing the pinned Zig version.
- Allowing AI output to determine mutation or doctest correctness.
- Introducing new third-party dependencies.

## Suggested implementation approach

1. Add focused failing tests and schema fixtures first.
2. Introduce shared containment helpers before touching individual adapters.
3. Apply adapter changes path-by-path, keeping deterministic core decisions outside CLI where possible.
4. Run targeted tests after each cluster, then the full build/test/validator gates.

## Dogfooding implications

zentinel dogfood and future autonomous audits should stop writing or reading outside the project through symlinks, stop leaking unredacted command evidence to advisory AI, preserve generated-command evidence for unusual but valid paths, and expose backend/sandbox/tool defects instead of hiding them.

## Follow-up tasks

- None predefined.
