# 032 Doctest Extraction

Sequential guard: start this task only after task 031 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement deterministic doctest case extraction and planning from parsed blocks.

## Scope

- Group parsed blocks into executable doctest cases.
- Assign stable doctest case IDs.
- Detect ambiguous or invalid block groupings.
- Produce a case inventory that can be rendered in tests.

## Files allowed to modify

- `src/doctest/extractor.zig`
- `src/doctest/case.zig`
- `src/doctest/parser.zig`
- `src/doctest/block.zig`
- `test/doctest_extraction_test.zig`
- `test/fixtures/doctest/extraction/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/doctest/runner.zig`
- `src/doctest/snapshot.zig`
- `src/cli.zig`
- `src/ai/**`

## Required tests

- Add a failing test for grouping `bash cli` with following `text output`.
- Add failing tests for `zig before` plus `zig after`, `toml config`, and `json expected` without a producer.
- Add a failing deterministic case ID snapshot.
- Add a failing case inventory snapshot that records durable `id`, anchor `source_ref`, secondary `block_refs`, and display-only source location fields as separate fields.
- Add a failing test that duplicate unlabeled identical cases in one file are rejected as ambiguous instead of receiving occurrence-based IDs.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Property tests required

- Case ordering is stable for repeated extraction.
- Case IDs change when grouped block content or explicit case labels change.
- Case IDs do not change when unrelated prose outside the case changes.
- Duplicate unlabeled identical cases in one file always produce the same extraction diagnostic.
- Ambiguous grouping always produces the same diagnostic.

## Acceptance criteria

- Extractor produces typed cases for all supported block groups.
- Invalid cases fail before execution.
- Case IDs and ordering are deterministic.
- No commands or compiler invocations occur.

## Non-goals

- Running doctests.
- Matching snapshots.
- Cache integration.
- Mutating doctest cases.

## TDD instructions

Add fixture markdown and expected case inventory first. The first test must fail because grouping or ID generation is absent, then implementation should make only that fixture pass before broadening.

## Suggested implementation approach

1. Build on the parser block list.
2. Use file path, block kind, explicit label when present, normalized grouping metadata, and content hash for durable `dt_` case IDs. Keep line numbers in `source_ref`, `block_refs`, and location fields only.
3. Define `source_ref` from the case anchor line: the first executable or producer block in the group. Expectation blocks belong in `block_refs` and must not be source-ref anchors.
4. Treat ambiguous expectations and duplicate unlabeled identical cases as invalid cases.
5. Keep extractor output serializable for future reports.

## Dogfooding implications

Extraction is the first deterministic surface for doctest dogfood and must remain stable.

## Follow-up tasks

- `tasks/033-doctest-runner.md`
