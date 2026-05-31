# 108 Deterministic Evidence Excerpts

Sequential guard: start this task only after task `107` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (High, determinism). `evidence.stderr_excerpt` embeds ASLR addresses and absolute paths raw (src/runner.zig:60); `normalizeForComparison` (src/report.zig:378) ignores excerpts, so real repeated runs are NOT normalized-equal.

## Goal

Make repeated-run report comparison actually deterministic for real test output. Captured command excerpts must be normalized (or excluded from the comparison surface) so two real runs over the same project produce normalized-equal reports.

## Scope

- Normalize non-deterministic content in stdout/stderr excerpts (hex pointer addresses, absolute machine paths) before they enter the report, or exclude excerpts from `normalizeForComparison`.
- Ensure `normalizeForComparison` and `evidenceEqual` agree with the chosen normalization.

## Files allowed to modify

- `src/runner.zig`
- `src/report.zig`
- `docs/REPORT_FORMAT.md`
- `test/report_determinism_test.zig`
- `test/fixtures/report/**`
- `artifacts/pipeline/108/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test that feeds two raw outcomes differing only in a `0x<hex>` address and an absolute path inside stderr, builds reports, and asserts `normalizeForComparison` makes them equal.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Two real repeated runs over the same project normalize to identical bytes even when mutants are killed via assertion stack traces.
- Pointer addresses and absolute paths in excerpts are normalized or excluded; docs/REPORT_FORMAT.md documents exactly what the comparison ignores.

## Non-goals

- Dropping evidence excerpts entirely from reports.
- Changing mutant IDs or classification.

## Suggested implementation approach

1. Add an excerpt normalizer (strip `0x[0-9a-f]+`, relativize/redact absolute paths) applied in `boundedExcerpt` or before comparison.
2. Extend `normalizeForComparison` to cover excerpts and align `evidenceEqual`.

## Dogfooding implications

zentinel's own dogfood determinism evidence can be produced from real runs instead of hand-authored fixtures.

## Follow-up tasks

- None predefined.
