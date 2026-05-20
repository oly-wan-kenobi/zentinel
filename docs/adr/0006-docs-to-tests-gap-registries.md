# ADR-0006: Docs-to-tests gap registries are regression-oriented

**Status:** Accepted
**Date:** 2026-05-19

## Context

zentinel now has normative docs for invariants, harness requirements, failure modes, mutators, schemas, style, and discipline. During bootstrap, most of those contracts are not yet implemented or tested.

A strict absolute coverage gate would fail every task until the whole system exists. A prose-only promise would let coverage gaps accumulate silently.

## Decision

zentinel uses committed docs-to-tests gap registries under `tests/coverage-gaps/`. Initial registries track invariants, failure modes, mutators, and schemas. Rows may be `covered = false` during bootstrap, but future tooling should use regression-oriented semantics:

- fail when a previously covered row becomes uncovered
- fail when a documented row is missing from its registry
- allow existing uncovered rows until the owning task lands

Registry files use JSON so the bootstrap validator can parse them with Python standard library tooling.

## Alternatives Considered

- **No registries until implementation exists.** Rejected because docs and tests would drift from day one.
- **Fail on every uncovered row immediately.** Rejected because it would block all early implementation work.
- **Use Markdown tables.** Rejected because they are harder to validate mechanically.
- **Use CI-only artifacts.** Rejected because artifacts expire and are not visible in review diffs.

## Consequences

**Positive.** The project gets an honest backlog of test gaps without blocking bootstrap. Future agents have a machine-readable target for closing gaps.

**Negative.** Registries add maintenance work when docs add new requirements.
