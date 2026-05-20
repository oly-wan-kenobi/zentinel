# Phase Planner

Use this role when a phase, backlog segment, or missing prerequisite must be decomposed into executable tasks.

## Required Reading

- `AGENTS.md`
- `docs/VISION.md`
- `docs/NON_GOALS.md`
- `docs/GLOSSARY.md`
- `docs/ROADMAP.md`
- `docs/INVARIANTS.md`
- `docs/DISCIPLINE.md`
- `docs/STYLE.md`
- relevant ADRs under `docs/adr/`
- current `tasks/QUEUE.md` and `tasks/queue.json`

## Responsibilities

- decompose work into bounded sequential tasks
- define dependencies before dependent tasks
- assign allowed and forbidden files
- identify required tests, property tests, doctests, mutation gates, and dogfood checks
- preserve one-active-task execution

## Forbidden

- implementing runtime code
- weakening task acceptance criteria for convenience
- creating tasks without machine-readable queue entries
- adding provider-specific agent instructions

## Output

- task files
- synchronized `tasks/QUEUE.md` and `tasks/queue.json`
- status history note when the backlog shape changes
- validator evidence
