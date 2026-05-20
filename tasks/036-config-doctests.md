# 036 Config Doctests

Sequential guard: start this task only after task 035 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Dogfood config documentation examples through normal doctest execution.

## Scope

- Convert public config examples to `toml config` or `toml config_fail`.
- Validate config snippets through the config parser and validator.
- Add expected diagnostics for invalid config examples.
- Include config doctests in normal `zentinel doctest` runs.

## Files allowed to modify

- `docs/CONFIG_SPEC.md`
- `src/doctest/**`
- `src/config.zig`
- `test/doctest_config_test.zig`
- `test/fixtures/doctest/config/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add failing doctest tests for minimal config, full config, experimental backend rejection, and unknown key diagnostics.
- Add a failing snapshot for config-fail diagnostic normalization.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Property tests required

- Config doctest normalization produces stable project-relative paths.
- Equivalent config snippets with reordered independent sections produce equivalent normalized config when the config parser permits it.
- Invalid config diagnostics are deterministic for repeated runs.

## Acceptance criteria

- Config examples in `docs/CONFIG_SPEC.md` are executable.
- Invalid config examples fail for the documented reason.
- Doctest reports identify config cases by doc path and line.
- No AI or mutation behavior is required.

## Non-goals

- Report doctests.
- Mutator spec doctests.
- Doctest cache.
- Remote AI provider behavior.

## TDD instructions

Start by adding a failing doctest for the minimal documented config. Do not change config parser behavior unless the doctest exposes a documented contract mismatch.

## Suggested implementation approach

1. Extend case planning for config snippets if needed.
2. Reuse config parser normalization.
3. Add diagnostics expectations for config failures.
4. Keep config docs concise and deterministic.

## Dogfooding implications

Config docs become executable contracts for the parser and validator.

## Follow-up tasks

- `tasks/037-mutator-spec-doctests.md`
