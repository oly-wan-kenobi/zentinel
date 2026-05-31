# 116 CLI And Spec Drift Cleanup

Sequential guard: start this task only after task `115` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (Low, spec-drift). Lower-impact drift: arithmetic mutator ignores `+=`/`-=` (src/mutators/arithmetic.zig:18); --help omits doctest subcommands and jsonl/junit; `doctest --format jsonl` is advertised but unimplemented; `not_implemented_commands` is vestigial (src/root.zig:267).

## Goal

Resolve the cluster of low-impact CLI/spec drift: reconcile `--help` and CLI_SPEC with the implemented surface, fix or drop the advertised `doctest --format jsonl`, decide compound-assignment arithmetic coverage, and remove the dead `not_implemented_commands` entries.

## Scope

- Sync help_text/CLI_SPEC with the actual commands, subcommands, and report formats.
- Either implement `doctest --format jsonl` or remove it from the docs.
- Decide whether arithmetic mutators should cover compound assignment; document the decision.
- Trim vestigial `not_implemented_commands` entries that `route` supersedes.

## Files allowed to modify

- `src/root.zig`
- `src/doctest_command.zig`
- `src/mutators/arithmetic.zig`
- `docs/CLI_SPEC.md`
- `docs/MUTATOR_SPEC.md`
- `test/cli_test.zig`
- `test/snapshots/**`
- `artifacts/pipeline/116/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test/snapshot asserting `--help` lists the real doctest subcommands and report formats, and that `doctest --format jsonl` either works or is absent from CLI_SPEC.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `--help`, CLI_SPEC, and the implemented CLI surface agree.
- No advertised `--format` value returns an unexpected usage error.
- Compound-assignment arithmetic coverage is either implemented or explicitly documented as out of scope; dead `not_implemented_commands` entries are removed.

## Non-goals

- Large new mutator work.
- Reworking the doctest report schema.

## Suggested implementation approach

1. Update help_text + snapshot and CLI_SPEC together.
2. Fix or remove jsonl doctest format; document the arithmetic decision; trim the dead list.

## Dogfooding implications

zentinel's own help and specs match its behavior, so its doctests over those docs stay honest.

## Follow-up tasks

- None predefined.
