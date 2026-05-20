# 018 Report Renderers

Sequential guard: start this task only after task 017 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Complete Phase 1 report rendering for text, JSON, JSONL, and the first CI-friendly summary format.

## Scope

- Improve human text report.
- Add shared global `--verbose` and `--quiet` parsing for report-producing commands.
- Ensure JSON report remains canonical.
- Add JSONL output for streaming-compatible consumers.
- Add the JUnit-compatible summary defined by `docs/REPORT_FORMAT.md` without broad CI integration.

## Files allowed to modify

- `src/report.zig`
- `src/cli.zig`
- `src/main.zig`
- `src/report_text.zig`
- `src/report_jsonl.zig`
- `src/report_junit.zig`
- `test/report_renderers_test.zig`
- `test/snapshots/report_*.txt`
- `test/snapshots/report_*.json`
- `test/snapshots/report_*.jsonl`
- `test/snapshots/report_*.xml`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/runner.zig`
- `src/ai/**`
- `src/cache.zig`

## Required tests

- Add failing snapshots for survivor-focused text output.
- Add failing JSONL snapshot.
- Add a failing JUnit XML snapshot.
- Add a failing JUnit status-mapping test for killed, survived, compile_error, timeout, skipped, invalid, run-level baseline_failed, and strict survivor-failing mode.
- Add a failing JUnit property test for structured command evidence under `result.commands[*]` (`command.original`, `command.argv`, `command.cwd`, `command.environment_policy`, `command.shell`, `phase`, `status`, `skip_reason`).
- Add failing schema compatibility test for JSON.
- Add failing test that summary counts are derived, not manually trusted.
- Add failing CLI tests that `--verbose` and `--quiet` parse according to `docs/CLI_SPEC.md` without changing deterministic JSON fields or hiding errors.
- Run `zig build test`.

## Acceptance criteria

- Text output matches `docs/REPORT_FORMAT.md` style.
- JSON remains canonical and deterministic.
- JSONL emits one stable object per line.
- JUnit summary follows the exact status mapping in `docs/REPORT_FORMAT.md` and represents survived mutants as failures only in strict survivor-failing mode.
- `--verbose` and `--quiet` are parseable for report-producing commands and affect only documented terminal verbosity.

## Non-goals

- AI advisory enrichment.
- HTML reports.
- Editor integrations.

## Suggested implementation approach

1. Keep renderers separate from report data construction.
2. Use stable key and entry ordering.
3. Normalize durations in snapshots.
4. Prefer compact text over academic score summaries.

## Dogfooding implications

Dogfood reports depend on clear survivor output. This task improves the review surface before self-mutation expands.

## Follow-up tasks

- `tasks/019-same-file-test-exclusion.md`
