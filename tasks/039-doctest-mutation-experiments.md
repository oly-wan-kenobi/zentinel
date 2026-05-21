# 039 Doctest Mutation Experiments

Sequential guard: start this task only after task 038 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Prototype `zentinel doctest --mutate` for fixture documentation without stabilizing the feature.

## Scope

- Add experimental command path for `zentinel doctest --mutate`.
- Mutate executable doctest snippets in fixture docs only.
- Reuse shared mutant model and result classification.
- Report killed and survived documentation mutants.
- Skip weak examples with deterministic reasons.

## Files allowed to modify

- `src/doctest/**`
- `src/mutant.zig`
- `src/mutant_runner.zig`
- `src/report.zig`
- `src/cli.zig`
- `test/doctest_mutation_experiment_test.zig`
- `test/fixtures/doctest/mutation/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/zir_backend.zig`
- `src/air_backend.zig`
- `src/ai/**`
- `docs/ROADMAP.md`
- `docs/DOCTEST_ROADMAP.md`

## Required tests

- Add failing fixture tests for one killed doctest mutant and one survived doctest mutant.
- Add a failing test for `no_behavioral_assertion` skip reason.
- Add a failing fixture test that mutation-aware doctest runner evidence includes `failure_kind`.
- Add a failing JSON report snapshot for doctest mutation results.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Required property tests

- Doctest mutation report ordering is stable.
- Worker count, if configurable, does not alter IDs or report order.
- Normal doctest failure prevents mutation execution for that case.
- Mutating a doctest snippet never modifies the documentation file.

## Acceptance criteria

- `zentinel doctest --mutate` works only for explicitly configured fixture docs.
- Documentation mutants reuse shared mutant/result semantics.
- The mutation-aware doctest runner evidence object includes `failure_kind`.
- Survivors are reported as documentation survivor diagnostics.
- The feature remains experimental and opt-in.

## Non-goals

- Stabilizing `doctest --mutate`.
- Running mutation-aware doctests over all public docs.
- AI survivor explanations.
- ZIR/AIR semantic mutation for doctests.

## TDD instructions

Add fixture docs and failing report snapshots first. Implement the smallest experimental path that mutates one supported doctest snippet and classifies the result through existing runner semantics.

## Suggested implementation approach

1. Require normal doctest pass before mutation.
2. Start with AST Phase 1 operators only.
3. Run mutation in generated doctest workspaces.
4. Reuse report structures where possible while preserving doctest context.

## Dogfooding implications

This task opens the path to mutation-aware documentation dogfood, but production docs should not be gated until later stabilization tasks.

## Follow-up tasks

- `tasks/055-ai-doctest-assistance.md`
- `tasks/061-doctest-mutate-stabilization.md`
