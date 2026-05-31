# 109 Wire Phase-2 Mutators Or Mark Them Preview

Sequential guard: start this task only after task `108` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding (High, dead-code). optional/error_path/integer_boundary/loop_boundary collectors are never called by the pipeline (src/run_command.zig:479, src/list_mutants_command.zig:78), yet config accepts their operator names and `release_acceptance.py` certifies '12 stable operators'.

## Goal

Reconcile advertised vs. emitted mutation operators. Either wire the four Phase-2 collectors into the run/list pipelines so their operators actually emit mutants, or downgrade them to `preview` in the spec/registry and make config reject enabling unwired operators.

## Scope

- Make the set of operators the pipeline can emit equal the set config/spec advertise as enabled-by-default `stable`.
- If wiring: call optional/error_path/integer_boundary/loop_boundary collectors from both generators. If demoting: mark them `preview` and reject them in `[mutators] enabled` with a clear error.

## Files allowed to modify

- `src/run_command.zig`
- `src/list_mutants_command.zig`
- `src/config.zig`
- `docs/MUTATOR_SPEC.md`
- `test/list_mutants_command_test.zig`
- `test/fixtures/mutators/**`
- `artifacts/pipeline/109/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test: a file containing optional/error/loop/integer sites with those operators enabled must either emit mutants (if wired) or be rejected at config load (if demoted) — current behavior (0 mutants, no error) must fail the test.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- No operator name that loads successfully in `[mutators] enabled` silently emits zero mutants on code that contains its target construct.
- docs/MUTATOR_SPEC.md stability labels match the operators the pipeline actually emits.
- scripts/release_acceptance.py's operator claim matches reality (see task 110).

## Non-goals

- Designing new mutation operators.
- Changing AST parsing.

## Suggested implementation approach

1. Decide wire-vs-demote per operator (prefer wiring the implemented collectors).
2. Update the generators or the config validator accordingly; sync MUTATOR_SPEC stability.

## Dogfooding implications

zentinel actually mutates optional/error-handling/loop code in its own dogfood, closing a silent coverage hole.

## Follow-up tasks

- None predefined.
