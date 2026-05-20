# 042 Context Packet System

Sequential guard: Start this task only after task `041` is complete and `tasks/status.json` names `042` as the next queued task.

## Goal

Specify the context packet format that fresh stateless subagents receive before performing a pipeline role.

## Scope

- Refine `docs/AGENT_CONTEXT_PACKETS.md`.
- Define required packet fields for task spec, allowed files, forbidden files, relevant docs, prior artifacts, constraints, and verification expectations.
- Define summarization rules and stale-context handling.
- Add schema and fixture documentation if the repository has schema validation support.

## Files allowed to modify

- `docs/AGENT_CONTEXT_PACKETS.md`
- `docs/ORCHESTRATION_SPEC.md`
- `docs/HANDOFF_CONTRACTS.md`
- `docs/AGENT_GUIDE.md`
- `schemas/pipeline.context.v1.schema.json`
- `schemas/pipeline.stale_context.v1.schema.json`
- `test/fixtures/pipeline/context_packet/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing fixture or schema validation case for a packet missing `task.id`, `role`, or `allowed_files`.
- Run `python3 scripts/validate_task_system.py`.
- If schema tooling exists, validate that stale `queue_revision` or missing prior artifact references are rejected.

## Required property tests

If packet validation code exists, add a deterministic property-style test that permutes context sections and proves semantic content, not JSON object key order, controls validity.

## Required doctests

No executable doctests are required until `zentinel doctest` exists. JSON examples must be stable and ready for future `json expected` validation.

## Mutation testing requirements

No mutation run is required unless context packet validation code is changed. If validation code exists, mutation checks must target required-field and stale-context branches.

## Acceptance criteria

- Packet fields are fully specified.
- Each pipeline role has a packet profile.
- Packet size management and summarization rules are explicit.
- Packet staleness checks are deterministic.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Do not implement subagent spawning.
- Do not add a prompt router.
- Do not rely on conversation history as durable state.

## Suggested implementation approach

1. Add a failing packet fixture that violates a required-field rule.
2. Update packet docs and schema together.
3. Add valid examples for Test Author, Implementer, Mutation Agent, Doctest Agent, and Verifier.
4. Cross-link the packet format from orchestration and handoff docs.

## Dogfooding implications

Context packets will eventually be archived for zentinel's own tasks so later agents can audit why a role made a decision.

## Follow-up tasks

- `043-mutation-gate.md`
- `047-sequential-task-locking.md`
