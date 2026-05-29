# Architecture Decision Records

This directory contains zentinel Architecture Decision Records (ADRs). ADRs capture decisions that future agents should not re-litigate without a deliberate superseding decision.

## How ADRs Work

**Numbering.** ADRs are numbered sequentially as `ADR-0001`, `ADR-0002`, and so on. Numbers are stable and never reused.

**Status.** Each ADR has one status:

- `Proposed`: written but not yet accepted.
- `Accepted`: binding for future work.
- `Superseded by ADR-NNNN`: replaced by a later ADR.
- `Deprecated`: no longer applies and has no direct replacement.

**Immutability.** Accepted ADR bodies are historical records. If a decision changes, write a new ADR and update the old status line to name the successor. Do not rewrite the old rationale to make history cleaner.

**Template.** Each ADR uses this order:

1. Title: `# ADR-NNNN: Short decision title`
2. Status and date
3. Context
4. Decision
5. Alternatives considered
6. Consequences

**Authority.** ADRs explain why. If a spec, task, or implementation conflicts with an accepted ADR, update the conflicting artifact or write a superseding ADR. Direct user, developer, and system instructions still outrank repository ADRs.

## Index

| ADR | Title | Status | Date |
| --- | --- | --- | --- |
| ADR-0001 | [Support latest stable Zig only](0001-latest-stable-zig-only.md) | Superseded by ADR-0007 | 2026-05-19 |
| ADR-0002 | [AST backend is the stable default](0002-ast-backend-stable-default.md) | Accepted | 2026-05-19 |
| ADR-0003 | [AI is advisory only](0003-ai-advisory-only.md) | Accepted | 2026-05-19 |
| ADR-0004 | [Sequential task system is the autonomous work authority](0004-sequential-task-system.md) | Accepted | 2026-05-19 |
| ADR-0005 | [Public artifacts are schema-versioned](0005-schema-versioned-artifacts.md) | Accepted | 2026-05-19 |
| ADR-0006 | [Docs-to-tests gap registries are regression-oriented](0006-docs-to-tests-gap-registries.md) | Accepted | 2026-05-19 |
| ADR-0007 | [Pin Zig 0.16.0 for this zentinel version](0007-pin-zig-0-16-0.md) | Accepted | 2026-05-20 |
| ADR-0008 | [Deterministic pipeline core with ports at side-effect boundaries](0008-deterministic-pipeline-core.md) | Accepted | 2026-05-23 |
