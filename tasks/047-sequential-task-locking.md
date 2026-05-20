# 047 Sequential Task Locking

Sequential guard: Start this task only after task `046` is complete and `tasks/status.json` names `047` as the next queued task.

## Goal

Specify active-task locking, queue semantics, branch ownership, and merge ordering for long-running sequential AI-agent development.

## Scope

- Refine `docs/SEQUENTIAL_EXECUTION_POLICY.md`.
- Define active lock ownership and stale lock recovery.
- Define queue transition rules across Markdown and JSON state.
- Define conflict prevention and branch ownership conventions.
- Connect lock failures to failure recovery.

## Files allowed to modify

- `docs/SEQUENTIAL_EXECUTION_POLICY.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/FAILURE_RECOVERY.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/AGENT_GUIDE.md`
- `test/fixtures/pipeline/sequential_locking/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing fixture or validation case for two active tasks before updating locking rules.
- Run `python3 scripts/validate_task_system.py`.
- If task-state validation code is extended, validate stale lock, mismatched Markdown/JSON, and invalid skip-ahead states.

## Required property tests

If queue validation code is changed, add property-style tests proving only one active task is accepted for any generated task list.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. Queue examples must use deterministic task IDs and no wall-clock values.

## Mutation testing requirements

No mutation run is required unless queue validation code changes. Once mutation testing exists, mutation-test active-lock and dependency-order validation branches.

## Acceptance criteria

- One-active-task rule is unambiguous.
- Markdown and JSON queue/status synchronization rules are explicit.
- Branch and merge order rules minimize conflicts.
- Stale lock recovery is deterministic and auditable.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not implement distributed locking.
- Do not add git hooks.
- Do not reorder existing tasks.

## Suggested implementation approach

1. Add a failing task-state fixture for the lock condition being clarified.
2. Update sequential policy and lifecycle docs.
3. Confirm existing validator behavior is described accurately.
4. Record validation output.

## Dogfooding implications

Sequential locking keeps dogfood reports attributable to exactly one active task and prevents merge-order ambiguity.

## Follow-up tasks

- `048-failure-recovery.md`
- `tasks/063-pipeline-metadata-validator.md`
