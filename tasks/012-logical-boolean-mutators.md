# 012 Logical and Boolean Mutators

Sequential guard: start this task only after task 011 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement AST candidates for `logical_and_or` and `boolean_literal`.

## Scope

- Generate `&& <-> ||`.
- Generate `true <-> false`.
- Preserve short-circuit operator spans.
- Avoid strings, comments, and test bodies if exclusion support already exists.

## Files allowed to modify

- `src/mutators/logical.zig`
- `src/mutators/boolean.zig`
- `src/ast_backend.zig`
- `test/mutators/logical_boolean_test.zig`
- `test/fixtures/mutators/logical_boolean/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/runner.zig`
- `src/sandbox.zig`
- `src/ai/**`

## Required tests

- Add failing tests for `&& -> ||` and `|| -> &&`.
- Add failing tests for `true -> false` and `false -> true`.
- Add a failing short-circuit fixture proving the operator span is exact.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- Logical and boolean candidates are generated exactly as specified.
- Candidate order remains stable with mixed mutator types.
- Boolean literals in non-code contexts are not mutated.
- No execution or reporting behavior changes except candidate availability.

## Non-goals

- Bitwise operator mutation.
- Semantic constant folding.
- AI classification.

## Suggested implementation approach

1. Add source-snippet fixtures that isolate each operator.
2. Implement recognizers using shared operator table style.
3. Verify mixed operator ordering through the collector.
4. Keep boolean literal handling syntax-aware.

## Dogfooding implications

Logical and boolean mutators will help identify missing branch tests in zentinel's own config and report code.

## Follow-up tasks

- `tasks/013-patch-sandbox.md`
