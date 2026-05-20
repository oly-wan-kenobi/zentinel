# 091 Analysis Risk Cleanup

Sequential guard: start this task only after task `090` is complete and `tasks/status.json` names `091` as the next queued task. No later-order task may begin until this task is complete.

## Goal

Close the non-blocking inconsistencies found by the latest deep analysis before project bootstrap starts.

## Scope

- Clarify that ADR-0001 is a historical superseded record and that ADR-0007 is the current Zig version authority.
- Align task-status handoff wording so it names the full pre-bootstrap hardening range through task `091`.
- Move task `000` behind this cleanup task in the sequential guard and dependency chain.
- Add a validator guardrail for the clarified handoff and ADR wording.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/091-analysis-risk-cleanup.md`
- `tasks/000-project-bootstrap.md`
- `docs/adr/0001-latest-stable-zig-only.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail requiring ADR-0001 to identify itself as a historical superseded record governed by ADR-0007 and Zig `0.16.0`.
- Add a failing validator guardrail requiring task-status handoff wording to include task `091` before project bootstrap.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating the affected prose.
- Run `python3 scripts/validate_task_system.py` after the contracts are aligned.

## Acceptance criteria

- ADR-0001 cannot be mistaken for current Zig policy by an agent skimming the file body.
- `tasks/STATUS.md` no longer says the pre-bootstrap hardening range stops at task `089` or task `090`.
- Task `000` depends on task `091` and its sequential guard names task `091`.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing runtime behavior.
- Changing the pinned Zig `0.16.0` decision.
- Reopening ADR-0007.
- Starting project bootstrap.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails against the stale handoff and ADR wording.
2. Update only the affected task-control and ADR prose.
3. Mark this cleanup task complete and leave project bootstrap as the next dependency-ready task.

## Dogfooding implications

No runtime behavior exists yet. This task removes stale governance signals before future agents start the implementation scaffold.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
