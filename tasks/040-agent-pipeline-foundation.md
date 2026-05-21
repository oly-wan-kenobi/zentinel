# 040 Agent Pipeline Foundation

Sequential guard: Start this task only after task `039` is complete and `tasks/status.json` names `040` as the next queued task.

## Goal

Establish the repository-visible foundation for the AI-agent task pipeline without implementing orchestration software. Future agents must be able to identify the required role sequence, complexity class, handoff artifacts, and verification gates for a task from checked-in specifications.

## Scope

- Review the pipeline architecture docs for consistency with `docs/AGENT_GUIDE.md`.
- Introduce any missing documentation links that make the pipeline discoverable from the agent entry points.
- Confirm that task lifecycle, orchestration, role, verification, escalation, and artifact specs agree on terminology.
- Keep the system sequential and stateless-subagent friendly.

## Files allowed to modify

- `docs/AGENT_PIPELINE_ARCHITECTURE.md`
- `docs/AGENT_ROLE_SPEC.md`
- `docs/TASK_LIFECYCLE.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/PIPELINE_ESCALATION_POLICY.md`
- `docs/AGENT_GUIDE.md`
- `scripts/validate_task_system.py`
- `tests/coverage-gaps/invariants.v1.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**`
- `build.zig`
- `build.zig.zon`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing documentation-contract check or validator fixture first if terminology cannot be verified by the existing validator.
- Add a failing structural guardrail proving I-019 TDD-first wording is preserved before updating the invariant gap row.
- Run `python3 scripts/validate_task_system.py`.
- Run a text search proving no new pipeline doc uses unsupported role names.

## Required property tests

No runtime property tests are required. If a metadata validator is introduced, add a property-style fixture that permutes role order and proves invalid orderings are rejected deterministically.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. Any command examples added to docs must use the doctest block formats defined in `docs/DOCTEST_BLOCK_FORMATS.md`.

## Mutation testing requirements

No mutation run is required because this task changes pipeline documentation only. Record that mutation testing is not applicable in the task handoff.

## Acceptance criteria

- Pipeline docs define `Phase Planner -> Task Queue Manager -> Orchestrator -> Stateless Subagents`.
- Every role named in the architecture appears in `docs/AGENT_ROLE_SPEC.md`.
- `docs/AGENT_GUIDE.md` points future agents to the pipeline docs.
- The task lifecycle remains sequential with one active task.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not implement an orchestrator.
- Do not add agent-spawning scripts.
- Do not change mutation engine behavior.
- Do not add CI jobs.

## Suggested implementation approach

1. Read the allowed docs and list all role names and pipeline stages.
2. Add a failing validation fixture or targeted text check if an inconsistency is found.
3. Patch only the inconsistent docs.
4. Run the task-system validator.
5. Record handoff evidence in status files.

## Dogfooding implications

This task prepares later dogfooding of the development process. It does not run zentinel against itself.

## Follow-up tasks

- `tasks/041-handoff-artifacts.md`
- `tasks/042-context-packet-system.md`
