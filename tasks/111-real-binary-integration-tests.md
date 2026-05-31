# 111 Add Real-Binary Integration Tests

Sequential guard: start this task only after task `110` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (Medium, test-quality). No test imports cli.zig/main.zig or spawns a real process; the real adapters (execProcess, setupWorkspace tree-copy, report writes, environ_map) are never exercised by `zig build test`.

## Goal

Add an end-to-end integration test that builds the binary and runs it against a tiny real Zig fixture project, asserting the produced report's classification, IDs, and selection — so the real I/O adapters in cli.zig are covered by CI.

## Scope

- A test (or scripts/ci.sh stage) that runs the built `zentinel run` over a committed fixture project and asserts kill/survive outcomes and report shape.
- Cover the per-mutant workspace creation and report writing paths.

## Files allowed to modify

- `build.zig`
- `test/integration_run_test.zig`
- `test/fixtures/integration/**`
- `scripts/ci.sh`
- `docs/CI_STRATEGY.md`
- `artifacts/pipeline/111/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `build.zig.zon`

## Required tests

- Add a failing integration test that runs the built binary over a fixture project with one killed and one surviving mutant and asserts the exact summary counts; it must fail before the harness wiring exists.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- CI exercises the real binary against a real fixture project (not only mock executors).
- A regression in execProcess/setupWorkspace/report-writing is caught by `zig build test` or scripts/ci.sh.

## Non-goals

- Replacing the existing mock-based unit tests.
- Benchmarking.

## Suggested implementation approach

1. Add a fixture project under test/fixtures/integration with inline + sibling tests.
2. Wire a build/test step that invokes the installed binary and diffs the normalized report.

## Dogfooding implications

zentinel's own CI proves the shipped binary works end-to-end, not just the deterministic core.

## Follow-up tasks

- None predefined.
