# Workflow: Task Test

Use this workflow after planning and before implementation.

## Steps

1. Load the planner handoff.
2. Dispatch or simulate `Test Author`.
3. Add the smallest meaningful failing tests, fixtures, property cases, doctests, or snapshots.
4. Run the targeted command and capture the expected failure.
5. Dispatch or simulate `Test Reviewer`.
6. If rejected, route fixes back to Test Author.
7. Do not proceed until the tests are approved.

## Output

- failing test evidence
- test coverage rationale
- test review approval or rejection
