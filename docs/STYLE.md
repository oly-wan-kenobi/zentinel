# Style

This document defines zentinel style rules for code, docs, tests, reports, and task artifacts. Discipline rules live in `docs/DISCIPLINE.md`; style rules keep the repository consistent enough for sequential agents to extend.

## How This Document Works

Rules are numbered `S-NNN`. Cite these numbers in reviews and handoffs when useful.

Prefer existing local patterns when they are more specific than this document. If a local pattern conflicts with this document, update the docs or the code path deliberately; do not drift silently.

## 1. Naming

**S-001.** Zig type names use `UpperCamelCase`.

**S-002.** Zig functions, local variables, struct fields, and file names use `snake_case`.

**S-003.** Constants use `SCREAMING_SNAKE_CASE` only when they are true constants. Prefer descriptive `snake_case` fields for config and report data.

**S-004.** Mutator operator names use stable `snake_case` strings, such as `comparison_boundary`.

**S-005.** Error codes use `ZNTL_<AREA>_<NAME>` and areas from `docs/ERROR_CODES.md`.

**S-006.** JSON fields use `snake_case`.

**S-007.** Test names describe the behavior or property, not the implementation detail or task number.

## 2. File and Module Layout

**S-100.** Keep public module roots small. Module roots declare structure and re-export intentionally; implementation belongs in focused files.

**S-101.** One file should have one primary responsibility. Split files that mix CLI parsing, mutation semantics, runner behavior, and report rendering.

**S-102.** Test files live near their concern: unit-style tests under `test/*_test.zig`, mutator fixtures under `test/fixtures/mutators/`, and snapshots under `test/snapshots/`.

**S-103.** Fixture directories use stable, descriptive names that match the behavior under test.

**S-104.** Generated or archived reports live under documented artifact paths. Do not scatter reports through source directories.

## 3. Comments and Documentation

**S-200.** Comments explain why a decision exists, not what the next line already says.

**S-201.** Public functions and types that affect deterministic behavior document the deterministic inputs they depend on.

**S-202.** Public functions that can fail document the error category or error code family they surface.

**S-203.** Bare TODO comments are forbidden. A TODO must cite a task file, issue, or ADR.

**S-204.** Inline examples in docs should use doctest block formats when they are intended to become executable.

**S-205.** Do not describe private implementation details in user-facing docs unless they affect the public contract.

## 4. CLI and Diagnostics

**S-300.** CLI text is concise, compiler-like, and deterministic.

**S-301.** CLI output emphasizes actionable survivors and concrete evidence, not mutation score as the headline.

**S-302.** Diagnostics follow the shape in `docs/ERROR_CODES.md`: code, message, location when available, and help text.

**S-303.** Help output is stable enough for snapshots. Avoid timestamps, environment-specific defaults, or host-specific paths.

**S-304.** User-facing text must not claim AI certainty. Advisory text uses evidence-based phrasing.

## 5. Tests, Fixtures, and Snapshots

**S-400.** Test names state the property: `comparison_boundary_reports_survivor`, not `test_comparison_1`.

**S-401.** Fixture source is intentionally small. One fixture should make one behavior easy to inspect.

**S-402.** Every mutation fixture documents target file, expected operators, compile expectation, and expected killed/survived result when executed.

**S-403.** Snapshot files use normalized paths, normalized durations, sorted JSON keys where supported, and stable schema versions.

**S-404.** Snapshot diffs are reviewed semantically. Do not accept snapshot churn as formatting noise.

**S-405.** Property-test reports name invariant categories, explicit seeds, generated case counts, and minimized failures when available.

## 6. JSON and Schemas

**S-500.** JSON examples in docs are minimal but complete enough to validate contract shape.

**S-501.** Schema files use deterministic key ordering where practical: `$schema`, `$id`, `title`, `type`, `additionalProperties`, `required`, `properties`.

**S-502.** Schema version strings match `docs/SCHEMA_REGISTRY.md` exactly.

**S-503.** Breaking schema changes require a new version and an ADR or explicit task acceptance criterion.
