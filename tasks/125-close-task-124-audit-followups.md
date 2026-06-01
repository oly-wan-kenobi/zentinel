# 125 Close Task 124 Audit Follow-Ups

Sequential guard: start this task only after task `124` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: the read-only adversarial multi-agent audit performed after task `124` was marked complete. Confirmed follow-up findings include mutation-aware doctest report/schema drift, incomplete `--config` containment in doctest and advisory AI paths, absolute `--root` config rejection, weak AI runner evidence validation, configured command parser drift, overclaimed adapter coverage, helper-only cleanup-warning coverage, doctest invalid-candidate diagnostic drift, stale schema gap metadata, and survivor evidence documentation drift.

## Goal

Resolve every high, medium, and low finding from the post-task-124 audit and implement the recommended follow-up tasks without weakening deterministic core behavior, AST-default semantics, pinned Zig `0.16.0` support, or advisory-only AI boundaries.

## Scope

- Align `zentinel doctest --mutate` output with the public `zentinel.doctest.report.v1` schema or explicitly version any alternate report shape.
- Enforce explicit `--config` containment for doctest and advisory AI settings paths instead of silently falling back to defaults.
- Support valid absolute `--root` project paths without treating the root-joined config path as an out-of-root read.
- Make mutation AI and doctest survivor AI reject partial or malformed command and runner evidence instead of defaulting required fields.
- Restore or document the configured command parser contract for quoted glob metacharacters.
- Add true adapter coverage for F-045 read-side symlink rejection and sandbox cleanup warning visibility, or narrow coverage claims to the executable evidence.
- Align doctest invalid-candidate diagnostics with I-011 and F-009, or document the stricter deterministic interpretation.
- Synchronize doctest survivor schema, docs, fixtures, and coverage-gap rows.

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
- `src/doctest/mutation_experiment.zig`
- `src/doctest/mutator_doctest.zig`
- `src/doctest/report.zig`
- `src/doctest/workspace.zig`
- `schemas/doctest.report.v1.schema.json`
- `schemas/ai.doctest.context.v1.schema.json`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/CLI_SPEC.md`
- `docs/CONFIG_SPEC.md`
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
- `test/check_command_test.zig`
- `test/cli_test.zig`
- `test/config_test.zig`
- `test/doctest_cli_command_test.zig`
- `test/doctest_mutate_stabilization_test.zig`
- `test/doctest_mutation_experiment_test.zig`
- `test/doctest_mutator_spec_test.zig`
- `test/doctest_runner_test.zig`
- `test/integration_run_test.zig`
- `test/list_mutants_command_test.zig`
- `test/mutant_runner_test.zig`
- `test/report_renderers_test.zig`
- `test/report_schema_test.zig`
- `test/run_command_test.zig`
- `test/sandbox_test.zig`
- `test/test_selection_test.zig`
- `test/zig_version_test.zig`
- `test/fixtures/ai/doctest_survivor/report.json`
- `test/fixtures/doctest/mutation_stabilization/killed.stable.json`
- `test/fixtures/doctest/mutation_stabilization/survived.stable.json`
- `scripts/validate_task_system.py`
- `tests/coverage-gaps/failure_modes.v1.json`
- `tests/coverage-gaps/invariants.v1.json`
- `tests/coverage-gaps/schemas.v1.json`
- `artifacts/pipeline/123/**`
- `artifacts/pipeline/124/**`
- `artifacts/pipeline/125/**`
- `tasks/123-resolve-follow-up-audit-findings.md`
- `tasks/124-close-task-122-123-audit-regressions.md`
- `tasks/125-close-task-124-audit-followups.md`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `build.zig`
- `build.zig.zon`
- `.claude/**`

## Required tests

- Add failing tests before implementation for every changed behavior. At minimum, cover schema-valid `doctest --mutate` JSON, explicit `--config` escape rejection in doctest and advisory AI paths, absolute `--root` config loading, strict AI runner evidence rejection, configured command parser quoted metacharacter behavior, adapter-level F-045 symlink rejection, cleanup warning emission through an executable seam, and doctest invalid-candidate diagnostics.
- Run targeted tests for changed modules.
- Run `zig build test --summary all`.
- Run `zig build`.
- Run `zig fmt --check src test`.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` while active and again after completion.

## Acceptance criteria

- `zentinel doctest --mutate` emits JSON that validates against the documented public schema version it claims.
- Explicit `--config` paths are rejected consistently across check, run, list-mutants, doctest, and advisory AI paths when they escape the selected project root through absolute paths, `..`, or symlinks.
- Valid absolute `--root` project paths can load project-root-relative config paths without weakening project-relative path checks.
- Mutation AI and doctest survivor AI reject reports missing any required command or runner evidence field that the context schema requires.
- Configured command parsing and `docs/CONFIG_SPEC.md` agree on quoted glob metacharacters.
- F-045 and cleanup-warning tests prove adapter-visible behavior, and coverage-gap rows do not overclaim untested paths.
- Doctest invalid-candidate diagnostics preserve the distinction between mutator invalid candidates and backend parse failures, or the docs and tests explicitly lock the chosen deterministic classification.
- `zentinel.ai.doctest.context.v1` coverage-gap metadata and doctest survivor docs match the implemented survivor flow.

## Non-goals

- Promoting ZIR or AIR from experimental status.
- Adding new stable mutators.
- Changing the pinned Zig version.
- Allowing AI output to determine mutation or doctest correctness.
- Introducing new third-party dependencies.

## Suggested implementation approach

1. Add failing contract and adapter tests for the confirmed audit findings.
2. Fix report/schema alignment first so doctest survivor AI consumes a valid deterministic artifact.
3. Harden config containment and AI report parsing.
4. Align parser/docs and invalid-candidate diagnostics.
5. Update only matching coverage-gap rows and run the required verification gates.

## Dogfooding implications

Future dogfood and advisory AI runs should consume schema-valid doctest mutation reports, reject unsafe config paths consistently, preserve exact deterministic evidence in AI prompts, and avoid hiding tool defects behind parse or fallback defaults.

## Follow-up tasks

- None predefined.
