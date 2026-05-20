# 076 Doctest Mutation Entry Identity

Sequential guard: start this task only after task 075 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Clarify mutation-aware doctest report identity so every documentation mutant entry has a durable ID separate from the original ordinary doctest case ID.

## Scope

- Define `dm_...` as the durable mutation-aware doctest report entry ID.
- Keep `dt_...` as the original ordinary doctest case ID under `case.mutation.doctest_case_id`.
- Keep `ds_...` as the survivor-only selector for `explain-survivor`.
- Update task 061 and task 067 requirements so agents implement and consume the separated identities.
- Add a structural validator guardrail for the identity split.
- Update the project bootstrap dependency guard to account for this inserted prerequisite.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/076-doctest-mutation-entry-identity.md`
- `tasks/000-project-bootstrap.md`
- `tasks/061-doctest-mutate-stabilization.md`
- `tasks/067-ai-doctest-survivor-assistance.md`
- `docs/DOCTEST_SPEC.md`
- `docs/GLOSSARY.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail that rejects mutation-aware doctest report wording without `dm_...` entry IDs.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating docs and task requirements.
- Run `python3 scripts/validate_task_system.py` after the identity split is documented.

## Acceptance criteria

- Mutation-aware doctest report entries use `case.id = "dm_..."`.
- The original ordinary doctest case remains available as `case.mutation.doctest_case_id = "dt_..."`.
- Non-survived mutation entries remain uniquely selectable in reports even when `case.mutation.survivor_ref = null`.
- Survivor refs remain `ds_...` and are valid only for survived mutation entries.
- No product implementation files are changed.

## Non-goals

- Implementing doctest mutation.
- Creating the future doctest report schema file.
- Changing ordinary doctest case ID derivation.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on missing `dm_...` identity wording.
2. Update the glossary and doctest report contract.
3. Update task 061 and task 067 so future implementation and AI commands use the split identities.
4. Complete the task and leave task 000 as the next dependency-ready task.

## Dogfooding implications

No dogfood run exists yet. This task makes future mutation-aware doctest reports unambiguous for agents and AI survivor assistance.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
