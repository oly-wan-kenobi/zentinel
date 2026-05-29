# 105 Architecture Boundary Enforcement

Sequential guard: start this task only after task `104` is complete and `tasks/status.json` names `105` as the active task. No later-order task may begin until this task is complete.

## Goal

Make zentinel's deterministic pipeline architecture hard for autonomous agents to drift from before project bootstrap.

## Scope

- Record the architecture decision that zentinel uses a deterministic pipeline plus functional core, with ports/adapters only at side-effect and advisory boundaries.
- Strengthen architecture, internal API, invariant, and agent-role docs so future agents have concrete dependency and review checks.
- Add validator guardrails that preserve the ADR, required architecture wording, role responsibilities, and task ordering before bootstrap.
- Update task `000` dependency wording so project bootstrap starts only after this architecture boundary hardening.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/105-architecture-boundary-enforcement.md`
- `docs/ARCHITECTURE.md`
- `docs/INTERNAL_API_CONTRACTS.md`
- `docs/INVARIANTS.md`
- `docs/GLOSSARY.md`
- `docs/DISCIPLINE.md`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/adr/README.md`
- `docs/adr/0008-deterministic-pipeline-core.md`
- `.agents/ORCHESTRATOR.md`
- `.agents/roles/architecture-reviewer.md`
- `.agents/roles/implementation-reviewer.md`
- `.agents/roles/verifier.md`
- `tests/coverage-gaps/invariants.v1.json`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing structural validator guardrail requiring the architecture ADR, deterministic pipeline boundary wording, architecture import-boundary review duties, and task `000` dependency on task `105`.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before docs fixes.
- Run `python3 scripts/validate_task_system.py` while task `105` is active after fixes.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run `jq empty tasks/status.json tasks/queue.json tests/coverage-gaps/invariants.v1.json`.
- Run `git diff --check`.
- Run `python3 scripts/validate_task_system.py` after marking task `105` complete.

## Acceptance criteria

- ADR-0008 is accepted and indexed.
- Architecture docs name deterministic pipeline plus functional core as the primary architecture and limit ports/adapters to side-effect and advisory boundaries.
- Internal API docs define machine-checkable layer categories and forbidden import edges for deterministic core, adapters, and advisory AI.
- Agent guide, autonomous protocol, orchestrator, and reviewer/verifier roles require architecture boundary checks for public-contract or implementation work.
- Invariant coverage records the new architecture boundary invariant.
- Task `000` depends on task `105` and names task `105` in its sequential guard.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing Zig source files.
- Adding runtime dependency injection machinery.
- Renaming existing modules.
- Changing report, config, CLI, AI, or schema shapes.

## Suggested implementation approach

1. Add the validator guardrail first and confirm it fails on the missing ADR and architecture-boundary wording.
2. Add ADR-0008 and index it.
3. Update architecture and internal API contracts with deterministic core, pipeline orchestration, adapter, and advisory AI boundaries.
4. Update agent-role docs so reviewers and verifiers must check import direction and ownership drift.
5. Add the new invariant and row-scoped gap registry entry.
6. Re-run validator, Python compilation, JSON syntax checks, and whitespace checks.

## Dogfooding implications

No zentinel runtime exists yet. This task makes the initial source scaffold and later implementation tasks start from validator-backed architecture boundaries.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
