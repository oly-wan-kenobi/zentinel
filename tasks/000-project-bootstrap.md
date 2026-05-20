# 000 Project Bootstrap

Sequential guard: start this task only after task 069 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Create the minimal Zig project scaffold for zentinel without implementing mutation behavior.

## Scope

- Add build files and source/test directories.
- Add a minimal root module that can compile.
- Add a smoke test proving `zig build test` runs.
- Preserve all existing documentation.

## Files allowed to modify

- `build.zig`
- `build.zig.zon`
- `src/root.zig`
- `src/main.zig`
- `test/bootstrap_test.zig`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `docs/**`

## Required tests

- First add a failing smoke test that imports the root module and asserts a stable project name or version constant.
- Run the targeted test and record the failure before implementation.
- Run `zig build test` after implementation.

## Acceptance criteria

- `zig build test` passes.
- The root module exposes deterministic compile-time constants for project name and initial version.
- No mutation behavior exists.
- No CLI commands beyond what is necessary for compilation exist.
- `tasks/STATUS.md` records completion, files changed, and tests run.

## Non-goals

- CLI parsing.
- Config parsing.
- Mutant model.
- Report schema.
- Any AI integration.

## Suggested implementation approach

1. Add the smallest `build.zig` that defines a module, executable target, and test step.
2. Add a root module with constants such as `project_name = "zentinel"`.
3. Add a test that imports the module through the build graph.
4. Keep naming aligned with `docs/VISION.md`.

## Dogfooding implications

This task creates the codebase shape that future dogfood tasks will mutate. No dogfood run is expected yet.

## Follow-up tasks

- `tasks/001-cli-shell.md`
