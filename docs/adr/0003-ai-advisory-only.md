# ADR-0003: AI is advisory only

**Status:** Accepted
**Date:** 2026-05-19

## Context

zentinel is designed for developers and AI agents, but mutation correctness must be determined by compiling and running selected tests. AI output is useful for explanations, clustering, and test suggestions, but it is provider-dependent and not reproducible enough to become a correctness oracle.

Existing docs already state that AI must not decide kill, survival, compile-error status, equivalent status, or schema compatibility.

## Decision

AI in zentinel is advisory only. AI may consume deterministic artifacts and produce explanations or suggestions under advisory fields. It must not write deterministic report fields, suppress mutants, decide equivalent status, or alter pass/fail semantics.

Default tests use deterministic stub providers. Live remote providers are optional and never required for default CI.

## Alternatives Considered

- **Let AI classify equivalent mutants.** Rejected because equivalence claims need deterministic proof or human-reviewed policy.
- **Let AI choose final survivor severity.** Rejected for deterministic reports. Advisory labels may exist under `advisory.ai`.
- **Require remote AI providers for best UX.** Rejected because zentinel must work offline and in CI.

## Consequences

**Positive.** Reports remain reproducible and auditable. AI can improve diagnosis without owning correctness.

**Negative.** Some helpful AI triage remains advisory and may require a human or deterministic rule before it changes gating.
