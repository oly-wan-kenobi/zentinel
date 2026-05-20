# 031 Doctest Parser

Sequential guard: start this task only after task 030 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement the Markdown fenced-block parser for doctest blocks.

## Scope

- Parse Markdown files for fenced code blocks.
- Preserve file path, line start, line end, raw info string, raw content, language, and tags.
- Recognize supported block formats from `docs/DOCTEST_BLOCK_FORMATS.md`.
- Produce deterministic diagnostics for malformed or unsupported doctest tags.

## Files allowed to modify

- `src/doctest/parser.zig`
- `src/doctest/block.zig`
- `src/error_codes.zig`
- `docs/ERROR_CODES.md`
- `test/doctest_parser_test.zig`
- `test/fixtures/doctest/parser/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/doctest/extractor.zig`
- `src/doctest/runner.zig`
- `src/doctest/snapshot.zig`
- `src/runner.zig`
- `src/ai/**`

## Required tests

- Add a failing parser test for one supported block before implementation.
- Add failing tests for line-number preservation, raw content preservation, and unsupported executable tag diagnostics using `ZNTL_DOCTEST_UNSUPPORTED_TAG`.
- Add a failing test for quadruple-backtick fenced blocks containing nested triple-backtick examples.
- Add a failing test that five-backtick fences are treated as documentation-only until a future task extends parser support.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Required property tests

- Parser output is deterministic across repeated parses of the same file.
- Re-serializing block metadata for comparison does not depend on map iteration.
- Random prose around fences does not change extracted block content or line numbers.

## Acceptance criteria

- Supported block info strings parse into typed metadata.
- Unsupported executable doctest tags fail clearly with documented doctest error codes.
- Ordinary unsupported documentation blocks remain documentation-only unless tagged as doctests.
- Parser does not execute code.

## Non-goals

- Grouping blocks into cases.
- Executing Zig or CLI commands.
- Snapshot matching.
- Mutation-aware doctests.

## TDD instructions

Write parser fixture tests first. Confirm they fail because no parser exists or because the parser does not classify the requested block, then implement the smallest parser needed to pass.

## Suggested implementation approach

1. Implement a line-oriented fence scanner.
2. Parse info strings with a small deterministic tokenizer.
3. Keep block classification separate from case extraction.
4. Use explicit enums for languages, kinds, and match modes.

## Dogfooding implications

The parser enables zentinel docs to become executable contracts in later tasks.

## Follow-up tasks

- `tasks/032-doctest-extraction.md`
