# 035 CLI Doctests

Sequential guard: start this task only after task 034 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Wire `zentinel doctest` for CLI documentation examples and dogfood the CLI spec.

## Scope

- Add the `zentinel doctest` command for normal doctest execution.
- Target CLI examples in `docs/CLI_SPEC.md`.
- Validate `bash cli` plus `text output` and `json expected` cases.
- Emit text and JSON doctest reports.

## Files allowed to modify

- `src/cli.zig`
- `src/main.zig`
- `src/doctest_command.zig`
- `src/doctest/**`
- `src/report.zig`
- `schemas/doctest.report.v1.schema.json`
- `docs/CLI_SPEC.md`
- `test/doctest_cli_command_test.zig`
- `test/fixtures/doctest/cli/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/cache.zig`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add failing CLI command tests for `zentinel doctest --file docs/CLI_SPEC.md`.
- Add failing report snapshots for passing and failing CLI doctests.
- Add a failing schema-validation test for `schemas/doctest.report.v1.schema.json` before emitting JSON doctest reports, including the full `run`, `summary`, `cases`, exact `case.kind` enum, structured `command`, bounded `result`, exact `case.result.snapshot` evidence, `diagnostics`, and `advisory.ai` fields documented in `docs/DOCTEST_SPEC.md`. This preserves the existing structured `command`, bounded `result`, `diagnostics`, and `advisory.ai` fields contract while making snapshot evidence exact.
- Add a failing report snapshot for an invalid doctest case with a stable diagnostic error code.
- Add a failing test for `--case <case-ref>` selection using both durable `dt_...` IDs and source-ref selectors.
- Add a failing test proving source-ref selectors resolve only the case anchor line and reject lines that point only at secondary expectation blocks.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Required property tests

- `--file` selection preserves case ordering.
- `--case` selection is stable for durable case IDs and anchor-line source-ref selectors.
- CLI doctest reports are equivalent across repeated runs except normalized durations.
- CLI doctest output remains deterministic with `--no-color`.

## Acceptance criteria

- CLI documentation examples can be executed through `zentinel doctest`.
- CLI doctest report format is deterministic and snapshot-tested.
- JSON doctest reports satisfy `zentinel.doctest.report.v1`.
- Failing CLI examples produce actionable diagnostics.
- No mutation-aware doctest behavior exists yet.

## Non-goals

- Config docs dogfood.
- Mutator spec doctests.
- Doctest cache.
- AI doctest explanations.

## TDD instructions

Write failing CLI doctest command tests first. The command should fail because it is unimplemented, then implementation should wire existing parser/extractor/runner/matcher modules.

## Suggested implementation approach

1. Add command dispatch without adding unrelated CLI options.
2. Reuse doctest modules rather than duplicating runner logic.
3. Keep report output compact and deterministic.
4. Update CLI docs only where needed to make examples executable.

## Dogfooding implications

CLI docs become the first self-hosted executable documentation surface.

## Follow-up tasks

- `tasks/036-config-doctests.md`
