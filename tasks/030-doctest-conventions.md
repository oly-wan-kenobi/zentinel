# 030 Doctest Conventions

Sequential guard: start this task only after task 029 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Introduce doctest authoring conventions into the repository without implementing doctest execution.

## Scope

- Add or refine documentation examples to use supported doctest block tags.
- Establish initial doctest fixture documentation under `test/fixtures/doctest`.
- Ensure public examples added by future tasks can become executable.
- Keep the work documentation-only except fixture markdown files.

## Files allowed to modify

- `docs/DOCTEST_*.md`
- `docs/CLI_SPEC.md`
- `docs/CONFIG_SPEC.md`
- `docs/REPORT_FORMAT.md`
- `docs/MUTATOR_SPEC.md`
- `test/fixtures/doctest/**/*.md`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `schemas/**`
- `scripts/**`
- `test/fixtures/**/*.zig`

## Required tests

- Add failing validation evidence by running `python3 scripts/validate_task_system.py` after creating fixture markdown but before status synchronization.
- Add documentation examples that future doctest extraction tests can target.
- Run `python3 scripts/validate_task_system.py`.

## Property tests required

- No executable property tests yet.
- Document the future properties: extraction order, case ID stability, and block classification determinism.

## Acceptance criteria

- Public doctest conventions are reflected in representative docs.
- Fixture markdown contains examples for `zig test`, `zig compile_fail`, `bash cli`, `text output`, `json expected`, `toml config`, `zig before`, and `zig after`.
- No doctest execution code exists.
- Task status is updated in Markdown and JSON.

## Non-goals

- Implementing a Markdown parser.
- Running doctests.
- Adding the `zentinel doctest` command.
- Updating report schemas.

## TDD instructions

This is a conventions task. The failing evidence is task-system validation around synchronized metadata and fixture-file presence. Do not add implementation tests until parser work starts in task 031.

## Suggested implementation approach

1. Add minimal fixture markdown covering every supported block format.
2. Keep examples deterministic and short.
3. Avoid changing prose unrelated to doctest conventions.
4. Confirm future parser tasks have stable fixture targets.

## Dogfooding implications

This task creates the documentation samples that later doctest dogfood runs will execute.

## Follow-up tasks

- `tasks/031-doctest-parser.md`
