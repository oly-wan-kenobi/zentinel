# Workflow: Task Verify

Use this workflow after implementation review and specialized gates.

## Steps

1. Dispatch or simulate `Verifier`.
2. Run targeted tests required by the task.
3. Run broader relevant tests.
4. Run mutation, property, doctest, snapshot, dogfood, or schema checks required by the task.
5. Run `python3 scripts/validate_task_system.py`.
6. Preserve command evidence.

## Stop Conditions

- a required gate fails
- command evidence is missing
- changed files violate task scope
- task state cannot be synchronized

## Output

- verifier verdict
- command evidence
- next Task Queue Manager instruction
