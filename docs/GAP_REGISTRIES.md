# Gap Registries

Gap registries connect zentinel's documentation contracts to executable tests. They are committed JSON files under `tests/coverage-gaps/`.

## Purpose

The registries prevent documentation from becoming decorative. If a doc states an invariant, failure mode, mutator, or schema contract, the corresponding registry tracks whether executable evidence covers it.

The initial registries are intentionally regression-oriented. Existing uncovered rows are allowed while the project bootstraps, but future tasks should not create new documented requirements without adding a registry row and planned test surface.

## Files

| Registry | File | Source document |
| --- | --- | --- |
| Invariants | `tests/coverage-gaps/invariants.v1.json` | `docs/INVARIANTS.md` |
| Failure modes | `tests/coverage-gaps/failure_modes.v1.json` | `docs/FAILURE_MODES.md` |
| Mutators | `tests/coverage-gaps/mutators.v1.json` | `docs/MUTATOR_SPEC.md` |
| Schemas | `tests/coverage-gaps/schemas.v1.json` | `docs/SCHEMA_REGISTRY.md` |

## Registry Row Semantics

Each row has:

- a stable identifier from the source document
- `covered`, a boolean saying whether executable tests currently cover it
- `tests`, a list of test or fixture paths when covered
- `deferred_to`, a task file or phase note when not covered
- `notes`, a short explanation

`covered = false` is allowed during bootstrap. A future gap-registry checker may use regression-only semantics:

- fail when a previously covered row becomes uncovered
- fail when a new documented row is added without a registry entry
- allow existing uncovered rows until their owning task lands

An uncovered row whose `deferred_to` points to a complete task is invalid unless the row is explicitly marked superseded. Once the owning task completes, the row must either become covered with executable evidence, move to a still-queued concrete owner, or document supersession.

## Agent Rules

- When adding a new invariant, failure mode, stable mutator, or schema contract, update the matching registry in the same task.
- When adding tests that cover a row, set `covered` to `true` and list the test paths.
- Covered row test paths must exist in the repository.
- Do not set `covered` to `true` for prose-only evidence.
- Do not delete uncovered rows to make the registry look better.
- Gap registry updates under `tests/coverage-gaps/<registry>.v1.json` are a row-scoped task exception: update only the matching row or newly required row for the active task's contract change unless the active task explicitly allows broader registry maintenance.
- When a completion changes a gap registry through the row-scoped exception, `completion_evidence.gap_registry_rows_changed` must list each changed registry path and row id so the validator can distinguish narrow row updates from broad registry cleanup. The validator compares actual changed row ids against `completion_evidence.gap_registry_rows_changed`.
