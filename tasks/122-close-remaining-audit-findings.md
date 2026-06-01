# 122 Close Remaining Audit Findings

Sequential guard: start this task only after task `121` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: Claude assessment of Codex audit findings in `CLAUDE_ASSESMENT_OF_CODEX_FINDINGS.md`, plus the root Codex findings artifacts. The remaining actionable issues are duplicate physical AST mutants across operators, non-fatal and partly untruthful Zig version handling on execution paths, doctest execution that inherits ambient environment and lacks timeout discipline, byte-sliced excerpts that can split UTF-8 codepoints, silent drops for unreadable or unparsable source files, generated-command preflight documentation drift, and several defense-in-depth gaps that could allow the same classes of defect to reappear.

## Goal

Close the remaining current actionable audit findings while preserving deterministic core behavior, stable AST-default semantics, and pinned Zig `0.16.0` support.

## Scope

- Deduplicate duplicate physical AST mutants while retaining deterministic candidate identity ordering.
- Make unsupported or missing Zig fatal for mutation run and doctest execution paths; do not synthesize the pinned Zig version for missing toolchains.
- Run doctest commands with the same minimal environment discipline and a bounded timeout used by test execution.
- Cap stdout and stderr excerpts at UTF-8 boundaries.
- Replace silent unreadable, unparsable, or source-missing skips with visible deterministic diagnostics or failures.
- Align report/test-selection documentation with generated-command preflight fallback behavior.
- Add defense-in-depth tests or code for latent findings that could otherwise reappear, including invalid candidate rejection, cache key completeness before reuse, AI command-array fidelity, and workspace copy failure visibility when current code still exposes the risk.

## Files allowed to modify

- `src/ast_backend.zig`
- `src/mutant.zig`
- `src/run_command.zig`
- `src/list_mutants_command.zig`
- `src/cli.zig`
- `src/runner.zig`
- `src/doctest/runner.zig`
- `src/report.zig`
- `src/cache.zig`
- `src/zig_version.zig`
- `src/ai/command.zig`
- `docs/REPORT_FORMAT.md`
- `docs/SANDBOX_SECURITY.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/PERFORMANCE_STRATEGY.md`
- `docs/TEST_SELECTION.md`
- `test/ast_candidate_ordering_test.zig`
- `test/mutators/loop_boundary_test.zig`
- `test/run_command_test.zig`
- `test/list_mutants_command_test.zig`
- `test/runner_baseline_test.zig`
- `test/doctest_runner_test.zig`
- `test/report_determinism_test.zig`
- `test/cache_key_test.zig`
- `test/snapshots/cache_metadata.json`
- `test/zig_version_test.zig`
- `test/cli_test.zig`
- `test/ai_command_test.zig`
- `test/integration_run_test.zig`
- `test/sandbox_test.zig`
- `CLAUDE_ASSESMENT_OF_CODEX_FINDINGS.md`
- `CODEX_FINDINGS.md`
- `CODEX_FINDINGS_FOLLOWUP_1.md`
- `CODEX_FINDINGS_FOLLOWUP_2.md`
- `CODEX_FINDINGS_FOLLOWUP_3.md`
- `tasks/122-close-remaining-audit-findings.md`
- `tasks/STATUS.md`
- `tasks/status.json`
- `artifacts/pipeline/122/**`

## Files forbidden to modify

- `build.zig`
- `build.zig.zon`
- `.claude/**`

## Required tests

- Add a failing test before implementation for each behavior changed by this task. At minimum, cover duplicate physical mutant deduplication, fatal unsupported or missing Zig classification helpers, UTF-8-safe excerpt caps, and parse/read/source-missing visibility; each new behavior test must fail before its fix.
- Run targeted tests for changed modules.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Duplicate physical edits from different AST operators are collapsed deterministically without changing canonical ordering for distinct mutants.
- `run` and doctest execution paths fail before executing tests when Zig is missing or not pinned `0.16.0`, and reports do not claim the pinned version when it was not found.
- Doctest command execution uses a minimal environment and bounded timeout.
- Runner and doctest output excerpts never truncate inside a UTF-8 codepoint.
- Source discovery, parsing, and candidate source lookup failures are surfaced deterministically rather than silently producing incomplete mutation sets.
- Documentation accurately states that failed generated-command preflights fall back to configured commands when that is the implemented behavior.
- Defense-in-depth tests prevent regression of invalid candidate handling, cache-key safety before reuse, AI command array fidelity, and workspace copy diagnostics where these risks apply to current code.

## Non-goals

- Adding new stable mutators or changing mutator semantics beyond duplicate physical-edit handling.
- Promoting ZIR or AIR from experimental status.
- Allowing AI output to determine mutation correctness.
- Changing the pinned Zig version.

## Suggested implementation approach

1. Start with small failing tests that isolate each current defect.
2. Prefer pure helpers for fatal Zig gating, UTF-8-safe excerpt bounds, and validation logic so execution-path tests stay deterministic.
3. Keep user-facing diagnostics stable and project-relative where paths are reported.
4. Update only the documentation needed to align with implemented behavior.

## Dogfooding implications

zentinel's own audit and future dogfood runs stop hiding missing mutants, duplicate work, untruthful environment claims, and malformed text evidence.

## Follow-up tasks

- None predefined.
