# Dogfooding

zentinel must test itself with zentinel as early as practical. Dogfooding is not a marketing milestone; it is a design pressure that keeps reports actionable, performance honest, and mutators grounded in real Zig code.

## Principles

- Dogfooding starts with fixtures, then moves into core modules.
- Dogfood runs must use stable defaults unless an experimental job is explicitly labeled.
- Dogfood failures are diagnostic evidence, not raw score shame.
- Survivors should become focused tests or documented equivalent-risk reviews.
- Dogfooding must never require AI to pass.

## Stages

| Stage | Scope | Required Before |
| --- | --- | --- |
| 1 | Fixture-only mutation | Phase 1 runner and reports. |
| 2 | Selected core modules | Config, report, and ID modules exist. |
| 3 | CI advisory job | Cache and timeouts are stable. |
| 4 | CI gating for deterministic regressions | Dogfood runtime is predictable. |
| 5 | Full self-mutation campaign | Core architecture is stable. |
| 6 | Doctest dogfood | Doctest extraction/execution and public docs are stable enough to run. |
| 7 | Mutation-aware doctest dogfood | `zentinel doctest --mutate` works on fixture docs. |

## Stage 1: Fixture-Only Mutation

Mutate only fixture projects under `test/fixtures`.

Goals:

- prove every stable mutator has killed and survived examples
- validate report determinism
- prevent same-file test mutation
- exercise compile-error classification

No production zentinel source is mutated in this stage.

## Stage 2: Selected Core Modules

Candidate modules:

- config parser and validator
- mutant ID generation
- report serializer
- test selection rules

Selection criteria:

- deterministic pure behavior
- focused unit tests already exist
- mutation run fits the budget documented in `docs/PERFORMANCE_STRATEGY.md`

Avoid mutating:

- CLI rendering before snapshots are stable
- runner process code before sandboxing is stable
- experimental backends

## Stage 3: CI Advisory Job

CI runs zentinel against selected internal modules and uploads reports as artifacts.

This stage should not fail the build solely for survivors. It should fail for:

- internal zentinel errors
- invalid mutant generation
- baseline failure
- nondeterministic report generation

## Stage 4: CI Gating

CI may fail on configured deterministic criteria:

- baseline failure
- new invalid mutants
- cache corruption
- report schema violations
- survivor count increases in explicitly protected modules

Survivor gating must be introduced conservatively and documented in `docs/CI_STRATEGY.md`.

## Stage 5: Full Self-Mutation

Full self-mutation runs across stable production modules.

Requirements:

- stable cache
- parallel runner
- deterministic scheduling
- archived reports
- triage process for equivalent-risk survivors

## Stage 6: Doctest Dogfood

Run `zentinel doctest` against zentinel's own public docs.

Initial targets:

- CLI examples
- config examples
- report JSON examples
- AI prompt/response examples
- doctest docs themselves

Doctest dogfood should fail on:

- invalid doctest blocks
- stale CLI output
- invalid config examples
- report examples that no longer satisfy schema
- nondeterministic snapshot output

## Stage 7: Mutation-Aware Doctest Dogfood

Run `zentinel doctest --mutate` against fixture docs and later mutator specs.

Initial targets:

- `docs/MUTATOR_SPEC.md` before/after examples
- doctest fixture docs under `test/fixtures`
- boundary and optional examples with explicit assertions

This stage should report documentation survivors as documentation quality issues, not as global mutation score failures.

## Dogfood Report Expectations

Dogfood reports should answer:

- what survived?
- why is it relevant to zentinel's own correctness?
- which tests are missing?
- did performance stay within budget?
- did any mutator generate invalid output?
- did executable documentation drift from implementation?
- did documentation examples survive mutation?

Dogfood reports should not center on a single percentage.

## Initial Production Dogfood

The initial advisory production dogfood runs zentinel over a small set of selected internal modules using `test/fixtures/dogfood/production/config.toml` (`scripts/dogfood-production.sh`). It is advisory only: survivors are reviewed, not score-driven, and only infrastructure or deterministic-core errors fail it. Repeated runs are deterministic — the committed reference reports `test/fixtures/dogfood/production/run1.report.json` and `run2.report.json` differ only in run id, timestamps, and durations and normalize to identical bytes. No invalid mutants may appear in protected production scope.

A dogfood survivor is never a vague quality note; it must become one of:

- a failing test task
- a documented equivalent-risk review
- a mutator bug task
- a test-selection bug task
- a doc example strengthening task

Dogfooding should preserve the same UX goal as product use: reports should be diagnostic, compiler-native, actionable, fast, and trustworthy.

## AI in Dogfooding

AI may be used to:

- explain internal survivors
- suggest missing tests
- cluster survivor themes
- suggest missing executable doctests
- explain doctest mutation survivors

AI must not:

- approve a release
- waive a survivor automatically
- decide equivalence
- rewrite tests without a separate explicit task
- decide doctest pass/fail or update snapshots automatically
