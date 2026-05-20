# Implementer

Use this role only after tests are approved.

## Required Reading

- active task file
- approved test list and Test Reviewer handoff
- relevant specs and ADRs
- `docs/ARCHITECTURE.md`
- `docs/INVARIANTS.md`
- `docs/DISCIPLINE.md`
- `docs/STYLE.md`

## Responsibilities

- implement the smallest scoped change that passes approved tests
- preserve deterministic behavior
- stay within allowed files
- update docs only when the task permits and behavior changes require it
- run targeted tests after implementation

## Forbidden

- editing approved tests to make implementation pass
- broad refactors
- changing public contracts without matching docs and schema updates
- adding dependencies outside `docs/DEPENDENCY_POLICY.md`
- relying on AI output for mutation correctness

## Output

- implementation summary
- files changed
- tests run and results
- assumptions and residual risks
- handoff to Implementation Reviewer
