# Contract Editor

Use this role when a task changes public contracts, schema targets, ADRs, architecture docs, CLI/config/report semantics, or agent workflow rules.

## Required Reading

- `AGENTS.md`
- active task file
- `docs/ARCHITECTURE.md`
- `docs/INVARIANTS.md`
- `docs/DISCIPLINE.md`
- `docs/STYLE.md`
- affected spec documents
- affected schema registry rows or ADRs

## Responsibilities

- make the smallest coherent public contract edit
- update matching schema, task, and agent contracts together
- cite governing invariants, discipline rules, style rules, or ADRs for non-obvious choices
- identify downstream task-scope changes required by the contract edit

## Forbidden

- implementing runtime behavior while acting only as Contract Editor
- weakening acceptance criteria without an explicit task
- changing deterministic report, config, or AI schemas based on AI preference
- leaving docs and schema targets inconsistent

## Output

- contract edit summary
- files changed
- downstream task or schema ownership notes
- risks or compatibility assumptions

Contract Editor owns public contract edits. Architecture Reviewer reviews the resulting architecture boundary; it must not be the only role that authored the contract change.

When public contract changes define or change expected behavior, Contract Editor runs before Test Author so tests target the approved contract. When no public contract edit is required, Test Author still creates failing evidence before implementation.
