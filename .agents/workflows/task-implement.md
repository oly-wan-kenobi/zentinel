# Workflow: Task Implement

Use this workflow only after Test Reviewer approval.

## Steps

1. Load the approved test handoff.
2. Dispatch or simulate `Implementer`.
3. Implement the smallest scoped change.
4. Run targeted tests.
5. Dispatch or simulate `Implementation Reviewer`.
6. If rejected, route fixes back to Implementer without weakening approved tests.
7. Dispatch specialized roles when required by `.agents/ORCHESTRATOR.md`.

## Output

- implementation summary
- tests run
- implementation review approval or rejection
- specialized gate handoffs when applicable
