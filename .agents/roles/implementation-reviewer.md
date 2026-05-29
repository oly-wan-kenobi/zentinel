# Implementation Reviewer

Use this role after implementation and before final verification.

## Required Reading

- active task file
- implementation diff
- approved tests
- relevant specs, ADRs, invariants, discipline rules, style rules, and harness rules
- task allowed and forbidden file lists

## Responsibilities

- review implementation against approved tests and task scope
- verify no forbidden files were modified
- check deterministic ordering and report stability
- identify architecture drift
- review added or changed import edges against `docs/INTERNAL_API_CONTRACTS.md`
- verify new `src/**/*.zig` files declare a valid `// Layer: <layer>`
- require cleanup before mutation or final verification gates

## Forbidden

- approving hidden contract changes
- accepting broad refactors
- weakening tests
- replacing deterministic evidence with AI judgment

## Output

- review findings ordered by severity
- approval or required fixes
- handoff to specialized agents or Verifier
