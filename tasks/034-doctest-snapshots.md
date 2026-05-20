# 034 Doctest Snapshots

Sequential guard: start this task only after task 033 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement doctest output normalization and snapshot matching for text, JSON, and diagnostics.

## Scope

- Normalize volatile output from doctest execution.
- Match `text output`, `json expected`, and `diagnostic expected` blocks.
- Support exact, contains, regex, subset, and unordered modes where specified.
- Produce deterministic mismatch diagnostics.

## Files allowed to modify

- `src/doctest/snapshot.zig`
- `src/doctest/normalizer.zig`
- `src/doctest/matcher.zig`
- `src/doctest/runner.zig`
- `src/error_codes.zig`
- `docs/ERROR_CODES.md`
- `test/doctest_snapshot_test.zig`
- `test/fixtures/doctest/snapshots/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/cli.zig`
- `src/mutators/**`
- `src/cache.zig`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add failing tests for exact text, contains text, regex text, JSON exact, JSON subset, JSON unordered, and diagnostic matching.
- Add failing tests for path, duration, run ID, and temp directory normalization.
- Add a failing mismatch diagnostic snapshot using `ZNTL_DOCTEST_SNAPSHOT_MISMATCH`.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Required property tests

- Normalization is idempotent.
- JSON object key order does not affect semantic JSON matching.
- Text normalization preserves meaningful line order.
- Snapshot mismatch output is deterministic across repeated runs.

## Acceptance criteria

- Doctest expectation blocks can validate actual runner output.
- Volatile output is normalized according to `docs/DOCTEST_BLOCK_FORMATS.md`.
- Mismatch diagnostics identify file, line, case ID, expected, actual evidence, and the documented doctest mismatch error code.
- Snapshot updates remain manual and task-scoped.

## Non-goals

- AI snapshot review.
- Cache integration.
- Mutation-aware doctests.
- Broad CLI `zentinel doctest` command wiring.

## TDD instructions

Start with failing pure normalizer tests before connecting matcher behavior to runner output. Do not update expected snapshots without reviewing the semantic diff.

## Suggested implementation approach

1. Implement pure normalizers first.
2. Implement JSON semantic matching separately from text matching.
3. Add diagnostic formatting last.
4. Keep all match results structured for future reports.

## Dogfooding implications

Snapshot matching is required before CLI/config/report docs can be safely dogfooded.

## Follow-up tasks

- `tasks/035-cli-doctests.md`
