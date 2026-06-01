# 117 Own Mutant Original Across Parse Teardown

Sequential guard: start this task only after task `116` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding F-1 (Critical, false verdict). Six of twelve stable operators (`error_catch_unreachable`, `errdefer_remove`, `optional_orelse_unreachable`, `integer_literal_boundary`, `boolean_literal`, and the for-range half of `loop_boundary`) capture `Mutant.original` as a borrowed slice of the parsed tree's `owned_source` (src/mutators/error_path.zig:62,99; src/mutators/optional.zig:62; src/mutators/integer_boundary.zig:70; src/mutators/loop_boundary.zig:113; src/mutators/boolean.zig:38,61). `generateCandidates` runs `defer parsed.deinit()` per file (src/run_command.zig), which frees `owned_source` (src/ast_backend.zig:62-68) before `sandbox.apply` reads `original`. The dangling slice no longer matches the source at the span, so every such mutant is classified `invalid` and never executed — a real surviving mutant (an untested error path) is hidden from the survivor count and the report shows a false "0 survivors". Operators that capture `original` via `tokenSlice` of a fixed-lexeme token (arithmetic, comparison, logical, `optional_null_check`, `loop_boundary` while) are safe only by accident. The defect is mode-dependent (Debug/ReleaseSafe poison the freed bytes to 0xAA -> `invalid`; ReleaseFast/ReleaseSmall read stale-correct bytes -> correct verdict by undefined behavior), so it is also a nondeterminism defect across optimize modes.

## Goal

Make `Mutant.original` outlive the parsed tree, so any candidate with a valid patch is executed and classified (`killed`/`survived`/`compile_error`/`timeout`/`compiler_crash`), never silently dropped to `invalid`, and the verdict is identical across optimize modes.

## Scope

- Own `original` (and any other field that borrows the parsed tree's source) in the long-lived collector allocator so it survives `parsed.deinit()`.
- Prefer a single-point fix in `ast_backend.Collector.add` that dupes `original` into `collector.allocator`; the per-mutator captures may stay as-is once the collector owns the bytes.
- Do not change classification semantics, mutator targeting, or the AST parser.

## Files allowed to modify

- `src/ast_backend.zig`
- `src/mutators/boolean.zig`
- `src/mutators/error_path.zig`
- `src/mutators/optional.zig`
- `src/mutators/integer_boundary.zig`
- `src/mutators/loop_boundary.zig`
- `test/mutators/**`
- `test/sandbox_test.zig`
- `test/integration_run_test.zig`
- `test/fixtures/integration/**`
- `artifacts/pipeline/117/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/runner.zig`
- `src/report.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test that drives the real pipeline (parse -> collect -> `parsed.deinit()` -> `sandbox.apply`) for `error_catch_unreachable` on an untested error path and asserts the patch applies and the mutant classifies as `survived` (today it is `invalid` with "source at span does not match mutant original text"). Add the same end-to-end assertion for one source-slice operator and one `number_literal` operator (`integer_literal_boundary`). The test must fail on a Debug build before the fix.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- For every stable operator, a candidate with a valid patch is never classified `invalid`; `invalid` remains reserved for genuine contract violations (I-011).
- The blast-radius matrix (one operator per run over source containing its target construct) shows zero `invalid` results on both Debug and ReleaseFast.
- `Mutant.original` no longer references freed parse memory; the verdict for a fixed project and operator is identical across Debug/ReleaseSafe/ReleaseFast/ReleaseSmall.
- The real-binary integration test exercises at least one non-arithmetic operator end-to-end.

## Non-goals

- Distinguishing `compile_error` from `killed` (task 118).
- Designing new mutation operators or changing AST parsing/targeting.
- Changing the sandbox patch-validation contract.

## Suggested implementation approach

1. In `ast_backend.Collector.add`, dupe `candidate.original` into `self.allocator` before appending, so the stored candidate owns its bytes; the read happens while `parsed` is still alive, so the dupe captures the correct text.
2. Confirm no other candidate field borrows the parsed tree (`file` comes from the caller's long-lived slice; `replacement` is static or allocator-owned).
3. Extend the integration fixture to include an error-path construct and assert a non-arithmetic operator is executed (not `invalid`).

## Dogfooding implications

zentinel can finally mutation-test its own error-handling, optional, boolean, integer-boundary, and loop code; enabling those operators stops silently reporting a false "0 survivors".

## Follow-up tasks

- None predefined.
