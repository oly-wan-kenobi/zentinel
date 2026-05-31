# 115 Harden AI Context Redaction

Sequential guard: start this task only after task `114` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (Medium, AI-boundary). Redaction (src/ai/redaction.zig) masks only configured label substrings; secret VALUES (api_key=SECRET, ghp_..., AKIA..., sk-ant-...) pass through. Latent today (providers are stubs) but a live hazard once a real provider is wired.

## Goal

Ensure AI context never ships secret values to a provider. Add value-shaped secret detection (or guarantee the context never contains raw secrets) so that connecting a real provider cannot leak credentials, while preserving fail-closed behavior on malformed patterns.

## Scope

- Add secret-value detection (common token shapes: AWS AKIA, GitHub ghp_, Anthropic sk-ant-, JWTs, PEM blocks) to redaction or assert the context excludes raw command output entirely.
- Document the redaction guarantee precisely (labels vs values).

## Files allowed to modify

- `src/ai/redaction.zig`
- `src/ai/context.zig`
- `src/ai/command.zig`
- `docs/AI_CONTEXT_SCHEMA.md`
- `test/ai_context_test.zig`
- `test/fixtures/ai/**`
- `artifacts/pipeline/115/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/report.zig`
- `src/run_command.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test asserting that values like `ghp_0123...`, `AKIA...`, and `sk-ant-...` (with no api_key/token label) are redacted from AI context, and that a malformed pattern still fails closed.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Realistic secret values are redacted from AI context regardless of surrounding label, or the context provably never contains raw command output.
- Malformed/unsupported redaction patterns still fail closed.
- docs/AI_CONTEXT_SCHEMA.md states exactly what redaction guarantees.

## Non-goals

- Implementing a remote provider.
- A general-purpose DLP engine.

## Suggested implementation approach

1. Add value-shape matchers to the redactor; keep the fail-closed compile path.
2. Add tests for value-shaped secrets and document the guarantee.

## Dogfooding implications

zentinel's advisory AI stays safe to enable on real projects without leaking credentials.

## Follow-up tasks

- None predefined.
