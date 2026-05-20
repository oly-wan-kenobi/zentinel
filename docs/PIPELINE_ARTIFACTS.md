# Pipeline Artifacts

Pipeline artifacts preserve context across stateless agents and long-running development.

## Artifact Root

```text
artifacts/pipeline/<task-id>/
```

Subdirectories:

```text
context/
handoffs/
reviews/
tests/
property/
doctest/
mutation/
verification/
decisions/
```

## Naming Conventions

```text
context/<role>.json
handoffs/<step>-<role>.json
reviews/test-review.md
reviews/implementation-review.md
mutation/report.json
mutation/triage.md
property/report.json
doctest/report.json
verification/report.md
verification/report.json
decisions/ADR-<task-id>-<short-name>.md
```

JSON handoffs are canonical. Optional Markdown summaries may use the same handoff basename with `.md`, but they are companion notes and cannot replace the JSON artifact required by `docs/HANDOFF_CONTRACTS.md`.

## Retention Policy

- Keep artifacts for completed tasks that affect public contracts, mutation semantics, reports, cache, runner, doctests, or AI contracts.
- Low-risk docs-only artifacts may be summarized in status after completion.
- Do not store secrets, raw home paths, or full temp workspaces.

## Traceability

Every artifact must include:

- task ID
- role
- timestamp or normalized run label
- command evidence when applicable
- source commit or working-tree state when available

Artifacts should be referenced from `tasks/STATUS.md` and `tasks/status.json`.
