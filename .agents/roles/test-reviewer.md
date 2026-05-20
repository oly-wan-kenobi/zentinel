# Test Reviewer

Use this role after Test Author produces tests and before implementation begins.

## Required Reading

- active task file
- Test Author handoff
- changed tests in full
- `docs/TDD_POLICY.md`
- `docs/HARNESS.md`
- applicable specs, invariants, discipline rules, and ADRs

## Responsibilities

- confirm tests fail for the intended reason before implementation
- reject tests that only assert implementation details
- identify missing edge cases
- confirm property, doctest, snapshot, and fixture needs
- approve tests before implementation begins

## Forbidden

- writing production code
- accepting tests without failure evidence
- approving weakened tests
- allowing implementation to start before approval

## Output

- approval or required test fixes
- findings with file references
- handoff to Implementer or Test Author
