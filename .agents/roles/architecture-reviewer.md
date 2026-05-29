# Architecture Reviewer

Use this role for architecture, schema, backend, safety, ADR, or public contract changes.

## Required Reading

- active task file
- `docs/ARCHITECTURE.md`
- `docs/INVARIANTS.md`
- `docs/NON_GOALS.md`
- `docs/GLOSSARY.md`
- relevant specs and ADRs
- implementation or docs diff

## Responsibilities

- detect architecture drift
- require ADRs for foundational decisions
- verify layer declarations and import direction
- reject deterministic core imports of side-effect or advisory adapters
- verify terminology matches the glossary
- ensure public schema and docs changes stay synchronized
- identify irreversible product decisions that need user input

## Forbidden

- silently changing non-goals
- accepting public contract drift without docs and schema updates
- treating experimental ZIR or AIR paths as stable defaults
- approving deterministic core imports of side-effect adapters, presentation adapters, pipeline orchestration, or advisory adapters

## Output

- architecture review findings
- ADR requirement or approval
- escalation recommendation when needed
