# ADR-0008: Deterministic pipeline core with ports at side-effect boundaries

Status: Accepted
Date: 2026-05-23

## Context

zentinel is a Zig-native mutation testing framework whose product promise depends on deterministic candidate generation, exact source spans, reproducible execution evidence, stable reports, and advisory-only AI. A classic hexagonal architecture would protect side-effect boundaries, but using it as the repo-wide architecture risks excessive service abstractions and generic repositories around a compiler-like pipeline.

The implementation will be performed by autonomous agents, so the architecture must be easy to verify mechanically. Agents need concrete module ownership, import direction, layer declarations, and validator-backed drift checks instead of broad architectural slogans.

## Decision

zentinel's primary architecture is a deterministic pipeline with a functional core.

Ports and adapters are allowed only at side-effect and advisory boundaries:

- CLI, CI, and editor entry points are presentation adapters.
- filesystem, process execution, sandbox workspace, cache storage, and report writers are side-effect adapters.
- AI provider integration is an advisory adapter.
- pipeline orchestration wires deterministic core modules to adapters.
- deterministic core modules own mutation models, source mapping, command parsing, candidate generation, selection rules, result classification, and canonical report data.

Ports and adapters are boundary tools, not the system architecture. They must not pull mutation semantics, classifier authority, stable ID logic, canonical ordering, or source mapping out of the deterministic core.

All future `src/**/*.zig` files must declare `// Layer: <layer>` using a layer from `docs/INTERNAL_API_CONTRACTS.md`. The task-system validator must reject deterministic core imports of side-effect or advisory adapters once source files exist.

## Alternatives Considered

Classic hexagonal architecture for the whole codebase:

- Rejected as the primary framing. It is useful at I/O boundaries, but it over-emphasizes generic port interfaces for a tool whose central risk is deterministic pipeline drift.

Layered CLI application:

- Rejected because simple CLI layering does not adequately protect AI advisory behavior, process execution, sandboxing, and report evidence boundaries.

Ad hoc module boundaries:

- Rejected because autonomous agents need machine-checkable contracts, not conventions that only humans remember.

## Consequences

Agents must preserve deterministic core ownership and cite this ADR, `I-022`, `D-603`, or `docs/INTERNAL_API_CONTRACTS.md` when a non-obvious import or module placement choice affects boundaries.

Reviewers must check new or changed import edges. Verifiers must run validator architecture boundary checks.

Future source scaffolding must include layer declarations from the first Zig files. If a task needs a forbidden dependency edge, it must insert a prerequisite contract task or update this ADR through a superseding ADR instead of bypassing the boundary locally.
