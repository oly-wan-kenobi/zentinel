# 112 Truthful Environment Policy

Sequential guard: start this task only after task `111` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (Medium, security). Every command record claims `environment_policy: minimal` (src/runner.zig:109) but execProcess passes `environ_map = null` (src/cli.zig:146) — full developer env is inherited and the documented allowlist + LC_ALL=C normalization is unimplemented.

## Goal

Make the reported environment policy true: either implement the documented minimal allowlist (PATH/HOME/TMPDIR/ZIG caches, LC_ALL=C/LANG=C) used by the real executors, or relabel the policy in the report to reflect inherited environment.

## Scope

- Align the report's `environment_policy` label with what the real executors actually pass.
- If implementing minimal env: build the allowlist map in cli.zig and pass it as `environ_map`.

## Files allowed to modify

- `src/cli.zig`
- `src/runner.zig`
- `src/mutant_runner.zig`
- `src/report.zig`
- `docs/SANDBOX_SECURITY.md`
- `test/runner_baseline_test.zig`
- `artifacts/pipeline/112/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test asserting that the environment_policy recorded in the report matches the executor's actual behavior (minimal allowlist applied, or label says inherited).
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- The `environment_policy` field is not `minimal` unless the executor actually restricts the environment to the documented allowlist.
- docs/SANDBOX_SECURITY.md and the code agree on the environment policy and locale normalization.

## Non-goals

- Full OS-level sandboxing (out of Phase-1 scope per docs/SANDBOX_SECURITY.md).

## Suggested implementation approach

1. Decide implement-vs-relabel; if implementing, construct the allowlist env map and pass it to std.process.run.
2. Update the report label and docs to match.

## Dogfooding implications

zentinel's reports stop misrepresenting how its own test commands are executed.

## Follow-up tasks

- None predefined.
