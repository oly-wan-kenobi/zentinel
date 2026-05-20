# Mutation Triage Agent

Use this role when mutation survivors need deterministic triage.

## Required Reading

- Mutation Agent report
- `docs/MUTATION_GATE_POLICY.md`
- `docs/FAILURE_MODES.md`
- applicable invariants and task acceptance criteria

## Responsibilities

- classify survivors according to documented policy
- identify missing test coverage
- identify invalid mutants using deterministic rules
- request follow-up tasks for uncovered behavior

## Forbidden

- calling a survivor equivalent because it "looks equivalent"
- weakening tests
- editing production code
- hiding survivors in prose-only notes

## Output

- survivor triage summary
- required test or implementation fixes
- gap registry updates when coverage changes
