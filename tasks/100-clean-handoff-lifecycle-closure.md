# 100 Clean Handoff Lifecycle Closure

Sequential guard: start only after task `099` is complete. Task `000` remains blocked until the stale clean-handoff baseline is cleared and the baseline lifecycle is validator-backed for committed handoffs.

## Goal

Remove the stale post-`099` clean handoff baseline, make committed clean worktrees reject lingering baselines, and close the small contract inconsistencies that could mislead autonomous agents before project bootstrap.

## Scope

- Add failing structural validator guardrails before implementation for:
  - clean worktrees requiring `clean_handoff_baseline: null`
  - baseline lifecycle wording in agent-facing handoff docs
  - status prose naming pre-bootstrap hardening through task `100`
  - task `041` explicitly reminding agents to update only matching coverage-gap rows when pipeline schemas become covered
- Clear the stale `clean_handoff_baseline` now that task `099` is committed and the worktree was clean before this task was inserted.
- Remove duplicated startup-validation wording from `docs/AUTONOMOUS_AGENT_PROTOCOL.md`.
- Keep Zig `0.16.0`, AST as the stable default backend, ZIR/AIR experimental status, deterministic core behavior, and Codex-only agent contracts unchanged.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/100-clean-handoff-lifecycle-closure.md`
- `.agents/workflows/task-done.md`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `build/**`
- `zig-out/**`
- `test/**/*.zig`
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

- `tasks/status.json` has `clean_handoff_baseline: null` after the committed task `099` handoff.
- The validator rejects non-null `clean_handoff_baseline` metadata when the worktree is clean.
- Agent-facing docs state that baselines are only for uncommitted carried-forward files and must be cleared after completed-task changes are committed.
- `tasks/STATUS.md` no longer presents task `098` as the final pre-bootstrap hardening closure.
- Task `041` explicitly mentions row-scoped gap-registry updates for pipeline schema rows when those contracts become covered.
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md` contains the pre-`041` active-state validator instruction once.
- Task-control Markdown and JSON remain synchronized.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Project bootstrap source creation.
- Runtime mutation behavior.
- New Zig tests or source modules.
- Changing the clean handoff baseline schema shape beyond validator lifecycle semantics.

## Suggested implementation approach

1. Activate this prerequisite and clear the stale baseline because the repo was clean at current `HEAD`.
2. Add validator guardrails so the current docs/status drift fails.
3. Align docs, status prose, task `041`, and protocol wording.
4. Complete the task only after active-scope validation and final complete-state validation pass.

## Dogfooding implications

This task removes autonomous-agent blockers before any dogfoodable zentinel runtime exists. No zentinel dogfood run is expected.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
