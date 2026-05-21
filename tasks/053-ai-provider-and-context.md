# 053 AI Provider and Context

Sequential guard: start this task only after task 052 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement deterministic AI provider plumbing, privacy redaction, and AI context construction.

## Scope

- Add disabled, stub, and local provider interfaces.
- Build AI context matching the structured object shapes in `schemas/ai.context.v1.schema.json` and `docs/AI_CONTEXT_SCHEMA.md`, including distinct backend and operator stability fields.
- Apply privacy redaction and source context limits.
- Keep AI advisory-only.

## Files allowed to modify

- `src/ai/provider.zig`
- `src/ai/context.zig`
- `src/ai/redaction.zig`
- `src/config.zig`
- `schemas/ai.context.v1.schema.json`
- `test/ai_context_test.zig`
- `test/fixtures/ai/context/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `src/runner.zig`

## Required tests

- Add a failing schema validation or snapshot test for AI context.
- Add a failing test that rejects an AI context missing required nested mutant, result, source, test, or operator fields.
- Add a failing test that result context uses the structured mutant command-results array from the report schema, rejects legacy single-`command` or `test_command`-only payloads, rejects empty `argv[0]`, requires deterministic `skip_reason` values for skipped command entries and result-level `skip_reason` for skipped mutant results, and allows only `environment_policy = "minimal"` in v1.
- Add a failing output-bound test proving stdout_excerpt and stderr_excerpt are capped at 4096 UTF-8 bytes on a safe character boundary before schema validation.
- Add a failing test that rejects `preview` as a backend stability while accepting it as an operator stability when explicitly represented.
- Add a failing test for redaction failure closing the AI flow.
- Add a failing config normalization test proving omitted `ai.redact_patterns` expands to `["(?i)api[_-]?key", "(?i)token"]`.
- Add a failing config validation test rejecting persisted `ai.provider = "remote"` unless `ai.remote_allowed = true` with `ZNTL_CONFIG_INVALID_VALUE`.
- Add a failing stub-provider test.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- AI context validates against the schema.
- The schema enforces the documented nested object shapes instead of accepting generic objects.
- AI context preserves command evidence as original command, parsed argv, cwd, environment policy, shell flag, mutant phase, command status, exit evidence, and skip reason.
- AI context stdout_excerpt and stderr_excerpt are capped at 4096 UTF-8 bytes on a safe character boundary; schema `maxLength` remains a secondary structural guard.
- AI context uses `backend_stability` for backend maturity and `operator_stability` for mutator maturity.
- Stub provider is deterministic.
- Remote providers remain disabled unless explicitly allowed. Persisted config that selects `provider = "remote"` with `remote_allowed = false` fails config validation; CLI overrides that request remote while config disallows it are owned by task 054 and fail with `ZNTL_AI_PROVIDER_NOT_ALLOWED`.
- AI cannot alter deterministic result fields.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing CLI AI commands.
- Calling live remote providers in default tests.
- Changing mutation result semantics.

## Suggested implementation approach

1. Start with provider interfaces and deterministic stubs.
2. Snapshot prompt payload ordering.
3. Reject malformed redaction config.
4. Keep provider outputs under advisory fields.

## Dogfooding implications

AI context snapshots become future doctest and dogfood contracts.

## Follow-up tasks

- `tasks/054-ai-advisory-commands.md`
