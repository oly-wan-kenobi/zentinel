# 066 Public Docs Doctest Coverage

Sequential guard: start this task only after task 065 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Make selected public contract docs executable through `zentinel doctest` after normal doctest support exists.

## Scope

- Convert selected CLI, config, report, AI, and doctest policy examples into executable doctest blocks.
- Add coverage fixtures for public docs that must remain executable.
- Ensure doctest evidence feeds verifier artifacts.
- Keep examples deterministic and snapshot-friendly.

## Files allowed to modify

- `docs/CLI_SPEC.md`
- `docs/CONFIG_SPEC.md`
- `docs/REPORT_FORMAT.md`
- `docs/AI_PROMPT_CONTRACTS.md`
- `docs/DOCTEST_POLICY.md`
- `docs/DOCTEST_BLOCK_FORMATS.md`
- `src/doctest/**`
- `test/public_docs_doctest_test.zig`
- `test/fixtures/doctest/public_docs/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add a failing doctest coverage test for at least one public CLI example.
- Add a failing doctest coverage test for at least one config example and one report JSON example.
- Add a failing verification fixture proving doctest evidence is referenced from the final verifier artifact.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Selected public docs execute through `zentinel doctest`.
- JSON examples either validate fully or are explicitly marked with supported subset semantics.
- Verifier artifacts reference doctest evidence for public docs.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Mutation-aware doctest gating for every public doc.
- AI-authored documentation rewrites.
- Replacing focused implementation tests with doctests.

## Suggested implementation approach

1. Start with one CLI example and prove the coverage test fails.
2. Add config and report examples after the CLI path is stable.
3. Normalize output before snapshotting.
4. Keep doc edits limited to executable contract examples.

## Dogfooding implications

Executable public docs become a durable dogfood surface for CLI, config, report, and AI prompt behavior.

## Follow-up tasks

- None predefined. Add concrete queued tasks if coverage gaps remain after this task.
