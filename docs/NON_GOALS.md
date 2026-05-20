# Non-Goals

This document records what zentinel will not do. It exists so agents do not spend task scope re-arguing rejected directions.

## Tags

- **[never]** means a deliberate no. Changing it requires a new ADR or a direct human instruction.
- **[not v1]** means out of scope for the minimum complete product. Revisit only with a written cost and verification argument.
- **[experimental only]** means allowed behind explicit opt-in but not part of stable defaults.

## Product Non-Goals

- **A general-purpose Zig test runner. [never]** zentinel invokes Zig test commands to evaluate mutants. It does not replace `zig test` or `zig build test`.
- **A fuzzing engine. [never]** zentinel may use property tests as evidence, but it does not generate runtime inputs as its core product.
- **A source formatter. [never]** zentinel patches source to run mutants and reports diffs. It does not reformat source as a feature.
- **A code coverage product. [never]** Coverage can inform gaps, but the product promise is mutation evidence, not line coverage.
- **A multi-language mutation framework. [never]** zentinel is Zig-native. Other languages are separate products.
- **An AI correctness judge. [never]** AI may explain evidence. It may not decide killed, survived, compile_error, invalid, skipped, or equivalent.
- **A compatibility layer for old Zig versions. [never]** zentinel targets only the latest stable Zig release for its own version.
- **An always-online service. [never]** The deterministic core must work offline and in CI without remote AI providers.

## Mutation Non-Goals

- **Mutating Zig `test` declarations by default. [never]** Tests are evidence, not normal mutation targets. Explicit test-mutation experiments must be separately labeled.
- **Suppressing possible equivalent mutants by intuition. [never]** Equivalent risk is metadata unless a deterministic, documented filter proves the skip.
- **Hiding compile errors as invalid mutants. [never]** Compile errors are normal deterministic results when a syntactically valid mutant does not type-check.
- **Using private compiler internals in stable paths. [never]** ZIR and AIR remain experimental unless the source mapping and version coupling are proven.
- **Generating multiple edits for a single mutant by default. [never]** A mutant is one documented source change unless a future ADR changes the model.

## Engineering Non-Goals

- **Multiple stable backend defaults. [never]** AST remains the stable default until explicitly superseded.
- **Remote provider tests in default CI. [never]** Default AI tests use deterministic stub providers.
- **Unpinned dependencies for core behavior. [never]** Dependency changes must follow `docs/DEPENDENCY_POLICY.md`.
- **Silent broad refactors during task execution. [never]** Task scope and allowed files bound the change.
- **Arbitrary global mutation score gates. [never]** Dogfood gating focuses on deterministic regressions, invalid mutants, and protected survivor changes.

## Process Non-Goals

- **Implementation before failing evidence. [never]** Behavior changes start with failing tests, fixtures, snapshots, or contract cases.
- **Prose-only follow-ups. [never]** Follow-up work must become concrete task metadata when it affects implementation.
- **Human coordination between every task. [never]** The task system must let agents continue sequentially unless a product, security, or compatibility decision is genuinely unresolved.
- **Chat history as durable state. [never]** Queue, status, docs, artifacts, and reports are the durable record.
