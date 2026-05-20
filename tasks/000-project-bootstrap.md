# 000 Project Bootstrap

Sequential guard: start this task only after task 089 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Create the minimal Zig project scaffold for zentinel without implementing mutation behavior.

## Scope

- Add build files and source/test directories.
- Add a minimal root module that can compile.
- Add a smoke test proving `zig build test` runs.
- Establish deterministic top-level `test/*_test.zig` discovery so task 001 and task 002 tests are included by `zig build test` without per-task `build.zig` edits.
- Preserve all existing documentation.

## Files allowed to modify

- `build.zig`
- `build.zig.zon`
- `src/root.zig`
- `src/main.zig`
- `test/bootstrap_test.zig`
- `test/bootstrap_discovery_test.zig`
- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `docs/**`

## Required tests

- First add a failing smoke test that imports the root module and asserts a stable project name or version constant.
- Add a failing `test/bootstrap_discovery_test.zig` that proves a second top-level `test/*_test.zig` file is included by `zig build test`.
- Run the targeted test and record the failure before implementation; before `build.zig` exists, the expected failure may be a missing build scaffold or unresolved root-module import.
- Run `zig build test` after implementation.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `zig build test` passes.
- `zig build test` runs every top-level `test/*_test.zig` file without requiring future tasks 001 and 002 to edit `build.zig`.
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

1. Add `test/bootstrap_test.zig` and `test/bootstrap_discovery_test.zig` before adding `build.zig`.
2. Run the targeted bootstrap command and record the expected missing build scaffold or unresolved root-module import failure.
3. Add the smallest `build.zig` that defines a module, executable target, and a deterministic top-level test discovery step for `test/*_test.zig`.
4. Add a root module with constants such as `project_name = "zentinel"`.
5. Keep naming aligned with `docs/VISION.md`.

## Dogfooding implications

This task creates the codebase shape that future dogfood tasks will mutate. No dogfood run is expected yet.

## Follow-up tasks

- `tasks/001-cli-shell.md`
