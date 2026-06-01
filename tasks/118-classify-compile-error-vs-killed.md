# 118 Classify Compile Error Versus Killed

Sequential guard: start this task only after task `117` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding F-2 (High, wrong deterministic field). `runner.classifyCommand` sets `failure_kind = .test_failure` for every non-zero exit and never emits `.compile_error` (src/runner.zig:118-130). Its only consumer, `terminalStatus`, therefore always takes the `else => .killed` branch (src/mutant_runner.zig:46-53), so a mutant whose project fails to compile is reported `killed`. docs/REPORT_FORMAT.md:202 defines `compile_error` = "Mutated project failed to compile" and `killed` = "Selected tests failed for the mutant"; docs/REPORT_FORMAT.md:232 requires `failure_kind` to be `compile_error` for normal Zig compile diagnostics and `test_failure` only after compilation succeeds; invariant I-010 makes `compile_error` a first-class deterministic result. The text report headline `"{killed} killed, {survived} survived"` (src/report_text.zig:49) has no compile_error column, so misclassified compile errors inflate the visible kill count and falsely attribute a compiler rejection to the test suite. Confirmed on the real binary (ReleaseFast): an `errdefer_remove` mutant that fails to compile reports `status=killed`, `failure_kind=test_failure`, with a compiler diagnostic in the stderr excerpt.

## Goal

Classify a mutant whose configured command fails to compile as `compile_error` (`failure_kind = .compile_error`), while a post-compile test/assertion failure stays `killed` (`failure_kind = .test_failure`), so the headline kill count counts only mutants the tests actually caught.

## Scope

- Distinguish a compile-phase failure from a test failure in the runner classification of a non-zero command result.
- Keep classification deterministic and derived only from command evidence; AI must not influence `failure_kind` or `status`.
- Do not change F-1's candidate lifetime or any mutator.

## Files allowed to modify

- `src/runner.zig`
- `src/mutant_runner.zig`
- `docs/REPORT_FORMAT.md`
- `test/runner_baseline_test.zig`
- `test/mutant_runner_test.zig`
- `test/snapshots/**`
- `artifacts/pipeline/118/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/report.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing classifier test: a mutant command result carrying a Zig compile diagnostic must classify as `compile_error` with `failure_kind = .compile_error` (today it is `killed`/`test_failure`); a result with a post-compile assertion failure must still classify as `killed`. The test must fail before the fix.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- A real-binary run of a compile-breaking mutant reports `compile_error` and increments the `compile_error` summary counter, not `killed`.
- A runtime-assert-failing mutant still reports `killed`.
- The documented `failure_kind`/status table in docs/REPORT_FORMAT.md matches behavior; `compile_error` is reachable in the `run` path.
- AI output cannot set or override `failure_kind` (I-001).

## Non-goals

- F-1's candidate-lifetime fix (task 117).
- Changing the `compile_error`/`killed` summary schema or `ResultStatus` enum (both already exist).
- Reworking mutation-score presentation beyond honest counting.

## Suggested implementation approach

1. Decide the compile-vs-test signal: detect a compile failure from the captured compiler diagnostics for pinned Zig 0.16 (a non-zero exit whose output is a compile diagnostic with no test run), keeping the heuristic deterministic and documented. If the detection strategy is genuinely ambiguous for a single `zig test <file>` command, record the smallest prerequisite or stop and request a product decision per the Autonomous Blocker Resolution protocol rather than guessing.
2. Set `failure_kind = .compile_error` in `classifyCommand` for that case; `terminalStatus` already maps it to `.compile_error`.
3. Update docs/REPORT_FORMAT.md only where wording must match the now-reachable behavior.

## Dogfooding implications

zentinel reports an honest kill count for its own suite: mutants the compiler rejects are surfaced as `compile_error`, not credited to the tests.

## Follow-up tasks

- None predefined.
