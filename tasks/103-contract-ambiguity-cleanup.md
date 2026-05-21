# 103 Contract Ambiguity Cleanup

Sequential guard: start this task only after task `102` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Remove the remaining contract ambiguities found by the pre-bootstrap repository analysis before project bootstrap starts.

## Scope

- Clarify that task `002` validates command list shape only, while task `005` owns full command syntax parsing in `src/command.zig`.
- Canonicalize command output excerpt bounds as UTF-8 bytes with schema `maxLength` as a secondary structural guard.
- Deduplicate the task-plan activation workflow so post-`041` activation is one branched step instead of repeated prose.
- Add a structural validator guardrail for pre-`063` structured chronology evidence labels on behavior-changing tasks after bootstrap starts.
- This is a structural validator guardrail and contract cleanup task.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/002-config-parser.md`
- `tasks/053-ai-provider-and-context.md`
- `tasks/103-contract-ambiguity-cleanup.md`
- `.agents/workflows/task-plan.md`
- `docs/CONFIG_SPEC.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/SCHEMA_REGISTRY.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing structural validator guardrail for the task `002`/task `005` command-parser ownership boundary.
- Add a failing structural validator guardrail for canonical UTF-8 byte output excerpt wording and schema `maxLength` caveat.
- Add a failing structural validator guardrail for the deduplicated task-plan activation branch.
- Add a failing structural validator guardrail requiring pre-`063` structured chronology labels for behavior-changing tasks after bootstrap starts.
- Run `python3 scripts/validate_task_system.py`.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run `jq empty tasks/status.json tasks/queue.json`.
- Run `git diff --check`.

## Acceptance criteria

- Task `002` cannot be read as owning command grammar parsing or `src/command.zig`.
- `docs/CONFIG_SPEC.md` documents the pre-task-`005` command validation boundary.
- Output excerpt bounds use one canonical UTF-8 byte rule before report writing or AI context construction.
- Docs explain that JSON Schema `maxLength` is a secondary character-count guard, not the canonical byte-limit authority.
- `.agents/workflows/task-plan.md` has one active-task transition with pre-`041` and post-`041` branches.
- Future behavior-changing tasks before task `063` must record the exact structured chronology labels when completing.
- Task `000` depends on task `103` before project bootstrap starts.

## Non-goals

- Implementing config parsing.
- Implementing command parsing.
- Changing report or AI context schemas.
- Starting project bootstrap.

## Suggested implementation approach

1. Add validator checks first and record the expected failure.
2. Update the narrow docs and task wording that the validator checks.
3. Sync task state after completion.

## Dogfooding implications

No zentinel runtime exists yet, so no dogfood run is expected. The cleanup reduces ambiguity for future dogfoodable implementation tasks.

## Follow-up tasks

None predefined.
