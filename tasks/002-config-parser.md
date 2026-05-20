# 002 Config Parser

Sequential guard: start this task only after task 001 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement parsing and validation for `zentinel.toml` according to `docs/CONFIG_SPEC.md`.

## Scope

- Load config from a path.
- Implement the deterministic in-tree TOML subset defined by `docs/CONFIG_SPEC.md` and `docs/DEPENDENCY_POLICY.md`.
- Apply documented defaults.
- Reject unknown keys and invalid values.
- Normalize project-relative paths.
- Keep experimental backends disabled unless explicitly opted in.
- Implement config-aware `zentinel init --test-command <command>` and `zentinel init --backend <ast>` output after parser validation exists.

## Files allowed to modify

- `src/config.zig`
- `src/config_toml.zig`
- `src/cli.zig`
- `src/main.zig`
- `test/cli_test.zig`
- `test/config_test.zig`
- `test/fixtures/config/**`
- `test/snapshots/init_config.toml`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ast_backend.zig`
- `src/runner.zig`
- `src/ai/**`

## Required tests

- Add a failing test for minimal config parsing.
- Add a failing parser test for tables, strings, booleans, integers, arrays of strings, and comments.
- Add a failing parse-error test for unsupported TOML syntax outside the documented subset.
- Add failing validation tests for unknown keys, empty test commands, invalid mode, and experimental backend misuse.
- Add a failing path normalization test.
- Add a failing defaults test proving omitted `project.exclude` expands exactly to `[".zig-cache/**", "zig-out/**", "test/**"]`.
- Add failing CLI/config integration tests proving `init --test-command <command>` and `init --backend ast` write config that parses successfully.
- Update the task 001 transitional CLI tests so `init --test-command <command>` and `init --backend ast` are no longer treated as invalid options once config-aware init exists.
- Add a failing test that `init --backend zir` or `init --backend air` is rejected by init instead of enabling experimental backends.
- Run `zig build test`.

## Acceptance criteria

- Minimal and full documented configs parse.
- Defaults match `docs/CONFIG_SPEC.md`.
- Validation errors identify section and key.
- `init` output from task 001 parses successfully.
- Config-aware init options write deterministic config and cannot enable experimental backends.
- Config parsing has no side effects outside reading the config file.
- No TOML dependency is added for Phase 0 config parsing.

## Non-goals

- Executing test commands.
- Discovering source files.
- AI provider setup.
- Backend implementation.

## Suggested implementation approach

1. Start with typed config structs.
2. Implement the small deterministic TOML subset in `src/config_toml.zig`.
3. Separate raw parse from validated normalized config.
4. Snapshot validation errors for deterministic wording.

## Dogfooding implications

Config validation is an early dogfood target because it is deterministic and branch-heavy.

## Follow-up tasks

- `tasks/003-test-harness.md`
