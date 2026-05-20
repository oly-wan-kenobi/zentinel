# 054 AI Advisory Commands

Sequential guard: start this task only after task 053 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement `explain`, `suggest`, and `review-tests` advisory AI commands.

## Scope

- Wire CLI commands to deterministic report input and AI providers.
- Validate AI responses against schemas.
- Render advisory output without changing reports unless explicitly requested.
- Reject malformed or unsafe model output.

## Files allowed to modify

- `src/ai/**`
- `src/cli.zig`
- `src/main.zig`
- `src/report.zig`
- `schemas/ai.prompt.v1.schema.json`
- `schemas/ai.explain.response.v1.schema.json`
- `schemas/ai.suggest.response.v1.schema.json`
- `schemas/ai.review_tests.response.v1.schema.json`
- `test/ai_commands_test.zig`
- `test/fixtures/ai/commands/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add failing CLI tests for AI-disabled command errors.
- Add failing CLI tests for `--ai-provider <disabled|stub|local|remote>`, including provider override behavior and `ZNTL_AI_PROVIDER_NOT_ALLOWED` when normalized config has `ai.remote_allowed = false`.
- Add failing CLI tests proving `--report <path>` selects the report, omitted `--report` uses `zig-out/zentinel/report.json`, and a missing default report fails with `ZNTL_AI_REPORT_NOT_FOUND` as a usage error.
- Add failing CLI tests proving `<mutant-ref>` accepts durable mutant IDs and display IDs scoped to the selected report, while unknown IDs and display IDs from another report are rejected with `ZNTL_AI_TARGET_NOT_FOUND`.
- Add a failing schema-validation test for the AI prompt request envelope before sending it to a provider, including validation that mutation AI flows embed a `context` object satisfying `zentinel.ai.context.v1`, reject schema-version-only placeholders, and reject unknown context schema versions.
- Add failing schema-validation tests for explain, suggest, and review-tests responses. Explain response tests must include the doctest-specific classification values because task 055 reuses `schemas/ai.explain.response.v1.schema.json` and may not redefine the enum.
- Add failing snapshot tests for stub-provider output.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- AI commands work with the stub provider.
- `explain` and `suggest` resolve `<mutant-ref>` according to `docs/CLI_SPEC.md`.
- AI commands document and implement command-local `--ai-provider` and `--report` behavior.
- Malformed responses are rejected deterministically.
- `schemas/ai.explain.response.v1.schema.json` accepts the mutation explain classifications and the doctest explain classifications documented in `docs/AI_PROMPT_CONTRACTS.md`.
- AI-only failures use the documented exit code.
- Deterministic reports remain valid without AI configured.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Remote provider integrations beyond interface compatibility.
- AI-owned mutation correctness.
- Doctest-specific AI flows.

## Suggested implementation approach

1. Parse reports as read-only input.
2. Validate before rendering.
3. Keep all suggestions project-relative.
4. Snapshot terminal and JSON output.

## Dogfooding implications

Stub AI command outputs become stable docs and doctest targets.

## Follow-up tasks

- `tasks/055-ai-doctest-assistance.md`
