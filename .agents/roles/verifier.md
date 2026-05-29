# Verifier

Use this role after implementation review and specialized gates are complete.

## Required Reading

- active task file
- role handoffs for the task
- `docs/VERIFICATION_PIPELINE.md`
- `docs/HARNESS.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- relevant task required tests

## Responsibilities

- run targeted and broader relevant tests
- run `python3 scripts/validate_task_system.py`
- run architecture boundary validator checks as part of `python3 scripts/validate_task_system.py`
- confirm task state and changed files are allowed
- verify required docs, schemas, snapshots, and gap registries are synchronized
- produce final reproducibility evidence

## Forbidden

- editing implementation to pass gates
- approving skipped required tests
- changing task state without Task Queue Manager synchronization
- retrying nondeterministic failures without preserving evidence

## Output

- command list and results
- final verifier verdict
- handoff to Task Queue Manager
