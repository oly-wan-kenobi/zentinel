# 126 Close Post-125 Adversarial Audit Findings

Sequential guard: start this task only after task `125` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete. Preserve the `clean_handoff_baseline` for task `125` while task `126` is active so prior uncommitted completion output is not attributed to this task.

## Source

Post-125 read-only adversarial multi-agent review requested on 2026-06-01.

## Goal

Resolve the accepted repository-wide audit findings without weakening zentinel's deterministic core, AST-default backend, pinned Zig `0.16.0` policy, task-state synchronization, or provider-neutral advisory AI boundary.

## Scope

This task covers the following accepted findings and follow-up work:

- Preserve operator-specific mutants when multiple logical candidates share one physical edit by filtering enabled operators before duplicate physical-edit dedupe.
- Either implement `[project].root` as the effective project root for CLI reads, writes, reports, generated workspaces, doctest files, and configured commands, or align the config contract and tests if the repository proves another behavior is intended.
- Reject invalid configured commands in `run` with the documented command-parse failure instead of misclassifying them as out-of-memory or internal errors.
- Emit real report `config_hash` values matching the public schema's full SHA-256 contract, or update schema/docs/tests together if the contract changes.
- Align `selection_preflight` schema, report producer, docs, and tests for skipped command evidence and `skip_reason`.
- Align doctest mutation report schema, docs, producer, fixtures, and AI context joins for mutation metadata, survivor references, and command evidence.
- Reject explicit `--config` failures in doctest and advisory AI paths before reading target docs or reports, and avoid silent fallback for missing or invalid explicit config.
- Harden advisory AI context validation and redaction for absolute paths, paths containing spaces, Windows-style paths, report-derived fields, runner statuses, failure kinds, skip reasons, command evidence, and prompt-injection-shaped input.
- Re-check filesystem containment for `--root`, explicit `--config`, symlink traversal, absolute path normalization, generated workspaces, doctest files, report output, and cleanup warnings.
- Clarify deterministic-core/advisory-adapter architecture boundaries where pure AI context validation/redaction lives in core but provider execution remains advisory.
- Replace false confidence in coverage-gap rows with stronger executable coverage or row wording that accurately describes the tested adapter surfaces.
- Add validator coverage for stale task/status prose and stale schema-registry claims discovered by the audit.
- Address lower-severity audit items such as shell-display quoting ambiguity, glob abuse cases, task-system stale handoff text, and schema/report examples that no longer validate.

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
- `src/project_model.zig`
- `src/report.zig`
- `src/ai/command.zig`
- `src/ai/context.zig`
- `src/ai/doctest_command.zig`
- `src/ai/redaction.zig`
- `src/doctest/mutation_experiment.zig`
- `src/doctest/mutator_doctest.zig`
- `src/doctest/report.zig`
- `src/doctest/workspace.zig`
- `schemas/report.v1.schema.json`
- `schemas/doctest.report.v1.schema.json`
- `schemas/ai.context.v1.schema.json`
- `schemas/ai.doctest.context.v1.schema.json`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/ARCHITECTURE.md`
- `docs/CLI_SPEC.md`
- `docs/CONFIG_SPEC.md`
- `docs/DOCTEST_SPEC.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/FAILURE_MODES.md`
- `docs/INTERNAL_API_CONTRACTS.md`
- `docs/MUTATOR_SPEC.md`
- `docs/REPORT_FORMAT.md`
- `docs/SANDBOX_SECURITY.md`
- `docs/SCHEMA_REGISTRY.md`
- `docs/TEST_SELECTION.md`
- `docs/ZIG_VERSION_POLICY.md`
- `docs/adr/0008-deterministic-pipeline-core.md`
- `scripts/validate_task_system.py`
- `test/ai_command_test.zig`
- `test/ai_context_test.zig`
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
- `test/project_model_test.zig`
- `test/report_determinism_test.zig`
- `test/report_renderers_test.zig`
- `test/report_schema_test.zig`
- `test/run_command_test.zig`
- `test/sandbox_test.zig`
- `test/test_selection_test.zig`
- `test/zig_version_test.zig`
- `test/fixtures/ai/doctest_survivor/report.json`
- `test/fixtures/doctest/mutation_stabilization/killed.stable.json`
- `test/fixtures/doctest/mutation_stabilization/survived.stable.json`
- `test/fixtures/test_selection/selection_metadata.json`
- `tests/coverage-gaps/failure_modes.v1.json`
- `tests/coverage-gaps/invariants.v1.json`
- `tests/coverage-gaps/mutators.v1.json`
- `tests/coverage-gaps/schemas.v1.json`
- `artifacts/pipeline/126/**`
- `tasks/126-close-post-125-adversarial-audit-findings.md`
- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `build.zig`
- `build.zig.zon`
- `.claude/**`

## Required tests

- Add or update failing tests before implementation for each behavior-bearing fix.
- At minimum, targeted tests must cover candidate filtering-before-dedupe, explicit config failures in doctest/advisory AI paths, invalid run command rejection, full report `config_hash`, skipped `selection_preflight` schema validity, doctest mutation report schema validity, AI redaction/validation of path and runner evidence fields, and task-system stale-prose validation.
- Run the targeted tests that cover changed modules.
- Run `zig build test --summary all`.
- Run `zig build`.
- Run `zig fmt --check src test`.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` while task `126` is active and again after completion-state updates.

## Acceptance criteria

- Every accepted high, medium, and low audit finding is resolved with code, docs, tests, schema, or task-system validation as appropriate.
- Findings judged false positive or not reproducible are documented in task completion evidence with repository evidence.
- Public schemas validate the reports and fixtures that the CLI and doctest flows emit.
- AI prompt context construction remains deterministic, provider-neutral, redacted before truncation, and advisory-only.
- Filesystem containment rejects escapes consistently for project roots, configs, doctest inputs, generated workspaces, reports, and cleanup paths.
- `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json` remain synchronized.
- No follow-up work remains as prose-only notes; unresolved work is either fixed or captured in task evidence as deliberately out of scope with repository justification.

## Non-goals

- Do not add or promote ZIR or AIR behavior beyond the existing experimental contracts.
- Do not introduce provider-specific agent runtime files or `.claude/` content.
- Do not use AI output as a correctness oracle.
- Do not change the pinned Zig version or support multiple Zig versions for this zentinel release.
- Do not reorder completed tasks except for task-control changes required to activate and complete this task.

## Suggested implementation approach

1. Activate this task, create the pipeline lock/context artifacts, and validate task state.
2. Add failing targeted tests for the strongest proven findings before implementation.
3. Fix deterministic-core, CLI/config, command parsing, report/schema, doctest, AI privacy, and task-system issues in small batches.
4. Re-run targeted tests after each batch and keep docs/schema/gap rows synchronized with behavior.
5. Run the full verification set and complete task state only after all accepted issues are closed.

## Dogfooding implications

Closing this task improves the trustworthiness of future zentinel dogfood runs by preventing missing mutants, false report-schema confidence, unsafe config fallback, misleading AI prompt context, and stale task-state handoffs from hiding real defects.

## Follow-up tasks

None predefined.
