# 119 Symlink-Safe Output Containment

Sequential guard: start this task only after task `118` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding F-3 (High, sandbox/integrity escape). zentinel asserts `--output` "must stay within the project root", enforced by `config.isOutsideRoot` (src/config.zig:197-204), but that check is string-only: it rejects absolute paths and literal `..` segments and never resolves symlinks. The write at src/cli.zig:386-389 (`root_dir.writeFile`) follows symlinks in the sub-path, so a symlinked directory inside the project tree that points outside it lets the report land anywhere on the filesystem. Confirmed on the real binary (Debug and ReleaseSafe): with `escape_link` a symlink to an out-of-root directory, `zentinel run --output escape_link/pwned.json` writes the report outside the project root while plain `--output ../x` is correctly rejected. The `cache.json` write (src/cli.zig:396-398) shares the same unguarded pattern. A mutation tester ingests untrusted third-party repositories, which can ship such a symlink, so this is a genuine escape-root primitive.

## Goal

Ensure `--output` (and the `cache.json` write) cannot create a file outside the project root even when a path component is a symlink that leaves the tree, while legitimate in-root output still works.

## Scope

- Make output containment resolve symlinks (or write through a root-pinned handle that refuses to traverse out of the tree), then re-check containment.
- Apply the same guard to `cache.json`.
- Do not weaken the existing string-level rejection of absolute paths and `..` segments.

## Files allowed to modify

- `src/cli.zig`
- `src/config.zig`
- `test/cli_test.zig`
- `test/config_test.zig`
- `artifacts/pipeline/119/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/runner.zig`
- `src/mutant_runner.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test that creates an in-tree symlink to an out-of-root directory and asserts `--output <link>/f.json` is rejected and writes nothing outside the root (today the write succeeds outside the root). Keep a passing case for legitimate in-root output.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- A symlink-escape `--output` is refused with a clear error and no file is created outside the project root, on Debug and ReleaseSafe.
- Legitimate in-root `--output` still writes the report.
- The `cache.json` write is guarded by the same containment check.
- Absolute-path and `..` rejections are preserved.

## Non-goals

- Read-side path containment for `--input-report`/`--config`/doctest `--file` (task 121).
- Changing report content or any mutation verdict.

## Suggested implementation approach

1. Before writing, resolve the final output path (realpath of the parent directory + the file name, or open the parent with no-follow semantics) and re-check it is inside the project root; reject otherwise.
2. Route the `cache.json` write through the same guard.

## Dogfooding implications

Running zentinel against an untrusted checkout can no longer be tricked into writing its report or cache outside the analyzed project.

## Follow-up tasks

- None predefined.
