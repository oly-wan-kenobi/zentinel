# 114 Scope ZIR/AIR Backends Honestly

Sequential guard: start this task only after task `113` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (Medium, spec-drift). zir_backend/air_backend (src/zir_backend.zig:61, src/air_backend.zig:63) re-tag the AST candidate set rather than doing IR analysis, and are reachable only from list-mutants, never `run`; ARCHITECTURE.md oversells them.

## Goal

Make the experimental-backend documentation and CLI surface match reality: state that `--backend` is list-mutants-only and that ZIR/AIR re-tag AST candidates without IR lowering, or implement real backend behavior. Remove the implication that `run` can use them.

## Scope

- Update docs (ARCHITECTURE/ZIR_BACKEND/AIR_BACKEND/CLI_SPEC) to state the relabel-only, list-only scope.
- Make `run --backend` either supported or explicitly rejected with a clear message.

## Files allowed to modify

- `src/cli.zig`
- `src/run_command.zig`
- `docs/ARCHITECTURE.md`
- `docs/ZIR_BACKEND.md`
- `docs/AIR_BACKEND.md`
- `docs/CLI_SPEC.md`
- `test/run_command_test.zig`
- `artifacts/pipeline/114/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test asserting `run --backend zir` is either supported or rejected with a documented error (not silently ignored), and that docs no longer claim IR-level analysis.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- User-facing docs describe ZIR/AIR as relabel prototypes with no IR analysis and `--backend` as list-mutants-only.
- `run --backend` behavior is explicit (supported or a clear error), never a silent no-op.

## Non-goals

- Implementing real ZIR/AIR lowering (a larger future effort).

## Suggested implementation approach

1. Reword the architecture/backend docs to match the code's own honest comments.
2. Add explicit handling/rejection of `run --backend`.

## Dogfooding implications

zentinel's docs stop overstating its own backend capabilities.

## Follow-up tasks

- None predefined.
