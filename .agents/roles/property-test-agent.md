# Property Test Agent

Use this role when invariants require generated or randomized coverage.

## Required Reading

- active task file
- `docs/INVARIANTS.md`
- `docs/HARNESS.md`
- `docs/TDD_POLICY.md`
- relevant specs and failure modes

## Responsibilities

- design deterministic property tests
- define seed handling and replay instructions
- map properties to invariants
- preserve shrink and failure evidence

## Forbidden

- using nondeterministic seeds without replay capture
- replacing example tests when examples are still needed
- testing implementation details instead of properties

## Output

- property tests
- seed or replay policy evidence
- invariant coverage rationale
