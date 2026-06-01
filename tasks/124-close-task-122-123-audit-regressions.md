# 124 Close Task 122/123 Audit Regressions

Sequential guard: start this task only after task `123` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: the read-only adversarial multi-agent audit of tasks `122` and `123` performed after task `123` was marked complete. The confirmed follow-up findings are cwd-relative explicit config reads, generated same-file commands still routed through command-string parsing, doctest AI snapshot-ref redaction gaps, untrusted AI report evidence defaults, doctest mutation invalid-candidate disappearance, missing cleanup-warning regression coverage, overclaimed symlink coverage rows, and low-severity diagnostic redaction/containment drift.

## Goal

Resolve every high, medium, and low finding from the task `122`/`123` audit and implement the recommended follow-up tasks without weakening deterministic core behavior, AST-default semantics, pinned Zig `0.16.0` support, or advisory-only AI boundaries.

## Scope

- Make explicit `--config` resolution and reads project-root-relative and reject cwd-relative or symlink escapes with containment diagnostics.
- Carry generated same-file selected commands as exact structured argv through selection preflight and mutant execution, using rendered command text only as report evidence.
- Redact doctest AI snapshot refs and report-derived project metadata before context construction; reject malformed untrusted AI input reports instead of fabricating command or runner evidence.
- Ensure doctest mutation candidate generation and doctest mutator-spec helpers cannot silently drop parse failures or structurally invalid candidates.
- Add deterministic regression coverage for sandbox cleanup warning visibility.
- Add CLI adapter coverage for read-side symlink containment and correct the matching coverage-gap rows.
- Normalize or redact raw user-supplied doctest paths/options in terminal diagnostics where they cross the documented privacy boundary.

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
- `tests/coverage-gaps/failure_modes.v1.json`
- `tests/coverage-gaps/invariants.v1.json`
- `tests/coverage-gaps/schemas.v1.json`
- `artifacts/pipeline/123/**`
- `artifacts/pipeline/124/**`
- `tasks/123-resolve-follow-up-audit-findings.md`
- `tasks/124-close-task-122-123-audit-regressions.md`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `build.zig`
- `build.zig.zon`
- `.claude/**`

## Required tests

- Add failing tests before implementation for each behavior changed by this task. At minimum, cover explicit `--config` outside-root rejection, generated same-file exact argv for command-parser metacharacter file names, doctest AI snapshot-ref redaction, malformed AI input report rejection, doctest mutation invalid-candidate/parse-failure visibility, cleanup warning visibility, and CLI adapter symlink containment.
- Run targeted tests for changed modules.
- Run `zig build test`.
- Run `zig build`.
- Run `zig fmt --check src test`.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` while active and again after completion.

## Acceptance criteria

- Explicit `--config` paths are interpreted relative to the selected project root, not process cwd, and cannot escape through absolute paths, `..`, or in-root symlinks.
- Generated same-file commands execute using exact argv for valid project-relative file names including spaces, glob bytes, and command-parser metacharacters; generated command text remains report evidence only.
- Doctest AI context redacts snapshot refs, command evidence, skip reasons, report-derived project metadata, and path/secret-like values before provider prompt construction.
- Mutation AI and doctest survivor AI reject malformed input reports that omit required command or runner evidence instead of inventing fallback evidence.
- Invalid doctest mutation candidates and doctest mutation parse failures are surfaced as deterministic invalid/diagnostic outcomes or explicit errors that match `docs/INVARIANTS.md` I-011 and `docs/FAILURE_MODES.md` F-009.
- Cleanup failures have an executable regression test proving the deterministic warning surface.
- F-045 and I-011 coverage-gap rows no longer overclaim untested behavior.
- Low-severity diagnostic leaks are either normalized/redacted or explicitly documented as outside the AI/privacy boundary.

## Non-goals

- Promoting ZIR or AIR from experimental status.
- Adding new stable mutators.
- Changing the pinned Zig version.
- Allowing AI output to determine mutation or doctest correctness.
- Introducing new third-party dependencies.
- Committing or rewriting task `123` history; this task builds on the current uncommitted task `123` worktree.

## Suggested implementation approach

1. Add focused failing tests and capture the expected failures.
2. Wire structured generated commands through selection and runner boundaries before touching reporting.
3. Harden config and AI validation/redaction paths.
4. Align doctest mutation invalid-candidate handling and coverage-gap rows.
5. Run targeted tests after each cluster, then the full build/test/validator gates.

## Dogfooding implications

Future zentinel dogfood and advisory AI runs should reject outside-root config paths, keep unusual but valid source filenames testable without shell parsing, avoid leaking report-sourced paths or secrets to AI, and surface tool defects instead of hiding them behind empty doctest mutation results.

## Follow-up tasks

- None predefined.
