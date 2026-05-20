# 090 Contract Traceability and Scope Hardening

Sequential guard: start this task only after task `089` is complete and `tasks/status.json` names `090` as the next queued task. No later-order task may begin until this task is complete.

## Goal

Close the remaining pre-bootstrap contract gaps around public diagnostic traceability, the pinned Zig version, validator scope, and preview-mutator release scope.

## Scope

- Require every public `ZNTL_...` error code to be represented by a numbered failure mode and gap-registry row.
- Pin the supported Zig version to `0.16.0` for this zentinel version and remove the moving latest-stable verification blocker from task `005`.
- Clarify that `python3 scripts/validate_task_system.py` is governance evidence only and cannot substitute for task-specific failing tests.
- Clarify that end-to-end completion and minimum complete product scope exclude preview mutator implementation unless a future task explicitly names a preview operator.
- Add validator guardrails for these contracts.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/090-contract-traceability-and-scope-hardening.md`
- `tasks/000-project-bootstrap.md`
- `tasks/001-cli-shell.md`
- `tasks/002-config-parser.md`
- `tasks/005-version-policy.md`
- `tasks/014-baseline-runner.md`
- `tasks/031-doctest-parser.md`
- `tasks/033-doctest-runner.md`
- `tasks/008-ast-parser-spike.md`
- `tasks/056-zir-backend-experiment.md`
- `AGENTS.md`
- `docs/VISION.md`
- `docs/NON_GOALS.md`
- `docs/GLOSSARY.md`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/TDD_POLICY.md`
- `docs/INVARIANTS.md`
- `docs/FAILURE_MODES.md`
- `docs/ERROR_CODES.md`
- `docs/ZIG_VERSION_POLICY.md`
- `docs/CONFIG_SPEC.md`
- `docs/CLI_SPEC.md`
- `docs/ZIG_SEMANTICS.md`
- `docs/AST_BACKEND.md`
- `docs/AIR_BACKEND.md`
- `docs/DEPENDENCY_POLICY.md`
- `docs/REPORT_FORMAT.md`
- `docs/AI_PROMPT_CONTRACTS.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/DOCTEST_SPEC.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/DOCTEST_ARCHITECTURE.md`
- `docs/MUTATOR_SPEC.md`
- `docs/PROJECT_ACCEPTANCE_CRITERIA.md`
- `docs/ROADMAP.md`
- `docs/adr/README.md`
- `docs/adr/0001-latest-stable-zig-only.md`
- `docs/adr/0007-pin-zig-0-16-0.md`
- `tests/coverage-gaps/failure_modes.v1.json`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- Add a failing validator guardrail requiring all public `ZNTL_...` codes from `docs/ERROR_CODES.md` to appear in `docs/FAILURE_MODES.md`.
- Add a failing validator guardrail requiring the pinned supported Zig version `0.16.0` in policy, invariants, and task `005`.
- Add a failing validator guardrail requiring task-specific failing evidence wording so a validator pass cannot be treated as product proof.
- Add a failing validator guardrail requiring minimum complete product and end-to-end wording to exclude preview mutator implementation.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating docs, gap rows, and task wording.
- Run `python3 scripts/validate_task_system.py` after the contracts are aligned.

## Acceptance criteria

- Every public error code in `docs/ERROR_CODES.md` has a concrete failure-mode trace in `docs/FAILURE_MODES.md`.
- `tests/coverage-gaps/failure_modes.v1.json` has matching rows for the added failure modes.
- Zig policy is pinned to `0.16.0` for this zentinel version and task `005` no longer depends on live latest-stable lookup.
- Future agents are told that validator success is not product semantic proof and does not replace active-task failing tests.
- Project acceptance and roadmap docs state that preview mutator implementation is outside end-to-end minimum-product scope unless a future task explicitly names the operator.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing any product runtime behavior.
- Adding Zig tests before project bootstrap exists.
- Implementing or promoting preview mutators.
- Downloading or detecting Zig.

## Suggested implementation approach

1. Add validator checks first and confirm they fail against the current docs.
2. Update docs, task requirements, ADR status, and gap registry rows to satisfy the guardrails.
3. Complete this pre-bootstrap hardening task and leave project bootstrap as the next dependency-ready task.

## Dogfooding implications

No runtime behavior exists yet. This task reduces the chance that future dogfood, release, or implementation agents use untraceable diagnostics, a moving Zig target, validator-only evidence, or preview mutators as accidental release scope.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
