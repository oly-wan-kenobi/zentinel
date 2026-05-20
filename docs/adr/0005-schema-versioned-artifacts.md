# ADR-0005: Public artifacts are schema-versioned

**Status:** Accepted
**Date:** 2026-05-19

## Context

zentinel emits reports, AI context payloads, AI responses, pipeline handoffs, task queues, task statuses, and future doctest artifacts. These artifacts are consumed by humans, CI, editor integrations, and agents.

Without explicit schema versions, agents cannot safely decide whether a report, cache entry, or handoff is compatible with the current implementation.

## Decision

Public machine-readable artifacts use explicit schema version strings registered in `docs/SCHEMA_REGISTRY.md`. Writers emit the documented version exactly. Breaking changes require a new version and tests.

Deterministic result fields must not move under advisory namespaces. Advisory AI fields may grow under advisory-owned fields when deterministic semantics do not change.

## Alternatives Considered

- **Rely on loose JSON shape.** Rejected because autonomous agents need compatibility checks.
- **Use only prose docs.** Rejected because schemas are executable implementation targets.
- **Version only reports.** Rejected because AI and pipeline artifacts also cross agent/session boundaries.

## Consequences

**Positive.** Consumers can validate contracts and reject incompatible artifacts clearly.

**Negative.** Adding or changing artifacts requires registry and schema maintenance.
