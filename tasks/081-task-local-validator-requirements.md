# 081 Task-Local Validator Requirements

Sequential guard: start this task only after task 080 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Make every queued task's local required-test list name the task-system validator so agents do not have to infer that completion gate only from global workflow docs.

## Scope

- Add a structural validator guardrail requiring non-superseded task files to mention `python3 scripts/validate_task_system.py`.
- Add the validator command to the task-local required tests for tasks `000` through `024`, including inserted task `019`.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/081-task-local-validator-requirements.md`
- `tasks/000-project-bootstrap.md`
- `tasks/001-cli-shell.md`
- `tasks/002-config-parser.md`
- `tasks/003-test-harness.md`
- `tasks/004-fixture-system.md`
- `tasks/005-version-policy.md`
- `tasks/006-report-schema.md`
- `tasks/007-mutant-model.md`
- `tasks/008-ast-parser-spike.md`
- `tasks/009-ast-candidate-ordering.md`
- `tasks/019-same-file-test-exclusion.md`
- `tasks/010-arithmetic-mutators.md`
- `tasks/011-comparison-mutators.md`
- `tasks/012-logical-boolean-mutators.md`
- `tasks/013-patch-sandbox.md`
- `tasks/014-baseline-runner.md`
- `tasks/015-mutant-runner.md`
- `tasks/016-minimal-run-command.md`
- `tasks/017-list-mutants-command.md`
- `tasks/018-report-renderers.md`
- `tasks/020-test-selection-same-file.md`
- `tasks/021-cache-key-design.md`
- `tasks/022-dogfood-fixture-run.md`
- `tasks/023-optional-null-mutators.md`
- `tasks/024-error-path-mutators.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `docs/**`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail that rejects non-superseded task files whose required tests omit `python3 scripts/validate_task_system.py`.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating task-local required-test lists.
- Run `python3 scripts/validate_task_system.py` after task-local required-test lists are aligned.

## Acceptance criteria

- Tasks `000` through `024`, including task `019`, list `python3 scripts/validate_task_system.py` in their required tests.
- The validator preserves the task-local validator-command requirement for future tasks.
- The global completion standard remains unchanged.
- No product implementation files are changed.

## Non-goals

- Changing the product behavior requested by any future implementation task.
- Reordering tasks other than this prerequisite insertion.
- Weakening task-specific targeted test requirements.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on the existing early queued tasks.
2. Add a validator-command bullet to each affected task's required-test list without changing the task-specific targeted tests.
3. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task makes the validator completion gate visible inside every queued task handoff.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
