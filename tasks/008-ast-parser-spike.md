# 008 AST Parser Spike

Sequential guard: start this task only after task 007 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Introduce a minimal AST/source parsing adapter for Zig files that can locate syntax nodes needed by Phase 1 mutators.

## Scope

- Parse Zig source files or tokenize enough structure for Phase 1 candidate discovery.
- Preserve byte offsets and line/column mapping.
- Exclude `test` bodies only if the support is natural here; otherwise leave exclusion to task 019.
- Emit diagnostics for parse failures.

## Files allowed to modify

- `src/ast_backend.zig`
- `src/source_map.zig`
- `src/mutant.zig`
- `test/ast_parser_test.zig`
- `test/fixtures/ast_parser/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/runner.zig`
- `src/sandbox.zig`
- `src/ai/**`

## Required tests

- Add a failing test for byte and line/column mapping.
- Add a failing test for parse diagnostics on invalid Zig source.
- Add a failing test that traversal order is deterministic.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Source mapping can round-trip byte offsets to line/column ranges.
- Parser adapter produces deterministic traversal for the same source.
- Parse errors are reported with file and location.
- No actual mutation operators are enabled yet.

## Non-goals

- Full Zig semantic analysis.
- Running `zig test`.
- Applying source patches.
- ZIR or AIR integration.

## Suggested implementation approach

1. Prefer Zig standard library parser support if available in pinned Zig `0.16.0`.
2. Keep adapter wrapped so future parser changes do not leak across modules.
3. Write fixtures with small source snippets.
4. Avoid building a custom parser unless no stable alternative exists.

## Dogfooding implications

Source mapping defects would make dogfood reports untrustworthy. This task establishes mapping tests before mutators depend on it.

## Follow-up tasks

- `tasks/009-ast-candidate-ordering.md`
