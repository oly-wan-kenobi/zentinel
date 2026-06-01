# 121 Align Read-Side Path Containment

Sequential guard: start this task only after task `120` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding F-5 (Low, integrity asymmetry). The write side guards `--output` with `config.isOutsideRoot`, but the read side does not: `--input-report` (src/cli.zig:673-674 and the analogous reads at :813-815, :897, :958, :1086) and `--config` (src/root.zig:417-420 returning the user path verbatim) accept both absolute paths and `..` traversal outside the project root. Confirmed on the real binary: `zentinel explain m --input-report /abs/outside.json` and `... --input-report ../../../tmp/outside.json` both succeed and surface the out-of-root file's fields. The attacker is the CLI invoker reading their own files, so no privilege boundary is crossed; the defect is the broken/asymmetric containment invariant, which should match the write-side guard or be documented as intentional.

## Goal

Make read-side path handling for `--input-report`, `--config`, and doctest `--file` consistent with the write-side containment guarantee: either reject out-of-root reads with a clear error, or document the asymmetry as intentional contract — but stop silently violating the stated root-containment invariant.

## Scope

- Apply (or explicitly and documentedly waive) root containment on the untrusted read paths, reusing the write-side helper hardened in task 119.
- Keep error messages clear and the exit codes consistent with existing CLI errors.

## Files allowed to modify

- `src/cli.zig`
- `src/root.zig`
- `test/cli_test.zig`
- `artifacts/pipeline/121/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/runner.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test asserting an out-of-root `--input-report` (absolute and `..`-traversal) is rejected with a clear error (or, if the asymmetry is intentionally kept, a test pinning the documented allowance); today both are silently accepted. The test must fail before the fix.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Read-side path containment for `--input-report`, `--config`, and doctest `--file` is consistent with the write-side guard, or the intentional exception is documented in docs/CLI_SPEC.md and pinned by a test.
- No regression to legitimate in-root reads.

## Non-goals

- Write-side symlink containment (task 119).
- Changing AI redaction (task 120) or any mutation verdict.

## Suggested implementation approach

1. Reuse the task-119 containment helper on the untrusted read paths, or document the deliberate read-side allowance in docs/CLI_SPEC.md and pin it with a test.
2. Keep `--config` resolution and existing exit codes unchanged for in-root paths.

## Dogfooding implications

zentinel's read and write path-containment story is consistent, so its own CLI contract no longer claims a guarantee it does not enforce.

## Follow-up tasks

- None predefined.
