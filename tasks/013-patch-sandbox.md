# 013 Patch Sandbox

Sequential guard: start this task only after task 012 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement a deterministic sandbox that can apply one source mutation without permanently changing the developer working tree.

## Scope

- Create isolated workspace or file-copy patch strategy.
- Apply one mutant replacement by byte span.
- Verify original source remains unchanged.
- Provide clear diagnostics for invalid spans.

## Files allowed to modify

- `src/sandbox.zig`
- `src/mutant.zig`
- `test/sandbox_test.zig`
- `test/fixtures/sandbox/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/runner.zig`
- `src/cli.zig`
- `src/mutators/**`
- `src/ai/**`

## Required tests

- Add a failing test that applies a single mutation to a copied workspace.
- Add a failing test that the original file remains unchanged.
- Add a failing test for invalid span rejection.
- Add a failing test for deterministic patched content.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- One mutant can be applied in isolation.
- The source tree is not modified.
- Invalid patches produce `invalid`-ready diagnostics.
- Patch application is independent of worker count.

## Non-goals

- Running `zig test`.
- Applying multiple mutants at once.
- Git integration.
- Cache integration.

## Suggested implementation approach

1. Start with copy-based sandboxing for simplicity.
2. Use byte offsets as authoritative patch boundaries.
3. Validate original text matches before replacement.
4. Keep cleanup behavior testable.

## Dogfooding implications

Safe sandboxing is required before zentinel can mutate its own files.

## Follow-up tasks

- `tasks/014-baseline-runner.md`
