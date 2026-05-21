# 102 Agent Workflow Cleanup

Sequential guard: start only after task `101` is complete. Task `000` remains queued until this prerequisite removes the remaining agent-workflow duplication and status-evidence precision drift found during deep repository analysis.

## Goal

Remove small agent-facing workflow inconsistencies before project bootstrap so autonomous agents start task `000` from a sharper task-system handoff.

## Scope

- Add failing structural validator guardrails before implementation for:
  - duplicate pre-`041` and post-`041` activation wording in `.agents/workflows/task-plan.md`
  - task `101` validation evidence explicitly naming both active-state and complete-state validator passes
  - status prose naming pre-bootstrap hardening through task `102`
- Deduplicate `.agents/workflows/task-plan.md` without changing the canonical startup order.
- Clarify task `101` completion evidence and current handoff notes.
- Keep Zig `0.16.0`, AST as the stable default backend, ZIR/AIR experimental status, deterministic core behavior, and Codex-only agent contracts unchanged.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/102-agent-workflow-cleanup.md`
- `.agents/workflows/task-plan.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `build/**`
- `zig-out/**`
- `test/**/*.zig`
- `docs/**`
- `schemas/**`
- `.claude/**`

## Required tests

- First add failing structural validator guardrails for the contracts in scope.
- Run `python3 scripts/validate_task_system.py` after adding guardrails and record the expected failures before fixing contracts.
- After implementation, run:

   ```bash
   python3 -m py_compile scripts/validate_task_system.py
   python3 scripts/validate_task_system.py
   jq empty tasks/status.json tasks/queue.json
   git diff --check
   ```

## Acceptance criteria

- `.agents/workflows/task-plan.md` contains one pre-`041` active-state validator instruction.
- `.agents/workflows/task-plan.md` contains one canonical post-`041` active-lock, context-packet, validator instruction.
- Task `101` completion evidence states that active-state validation passed before completion and complete-state validation passed after completion.
- `tasks/STATUS.md` names task `102` as the current pre-bootstrap hardening closure while this task is active and then records its completion.
- Task-control Markdown and JSON remain synchronized.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Project bootstrap source creation.
- Runtime mutation behavior.
- New Zig tests or source modules.
- Changing product specs, schemas, ADRs, or public CLI/config/report contracts.

## Suggested implementation approach

1. Activate this prerequisite before task `000`.
2. Add validator guardrails so the current duplicated workflow wording and stale validation-evidence wording fail.
3. Align task-plan wording, task `101` evidence notes, task `000` dependency guard, and status prose.
4. Complete the task only after active-scope validation and final complete-state validation pass.

## Dogfooding implications

This task removes autonomous-agent workflow noise before any dogfoodable zentinel runtime exists. No zentinel dogfood run is expected.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
