# Harness

This document specifies zentinel's test harness surface. zentinel does not need Kumo-style deterministic simulation, but it does need a deterministic fixture, sandbox, runner, doctest, property-test, and dogfood harness so agents can prove behavior without relying on judgment.

## How This Document Works

Harness requirements are numbered `H-NNN`. Each requirement has a rationale, status, and enforcement mechanism.

Statuses:

- `planned`: required but not implemented.
- `documented`: specified in docs and tasks.
- `tested`: covered by tests or fixtures.
- `enforced`: blocked by CI, validator, schema, or build configuration.

## Harness Model

The harness has six cooperating parts:

- **Fixture harness**: builds small Zig projects and expected outputs.
- **Patch sandbox harness**: applies one mutant in an isolated workspace and verifies cleanup.
- **Runner harness**: records baseline and mutant command evidence.
- **Property-test harness**: runs seeded generators for deterministic surfaces.
- **Doctest harness**: extracts, runs, normalizes, and matches executable docs.
- **Dogfood harness**: runs zentinel against zentinel fixtures and selected source modules.

The harness produces evidence for agents and CI. It is not an AI evaluation loop.

## Determinism

**H-001.** Harness runs that affect reports use project-relative paths and normalized separators.
- *Rationale.* Fixtures must pass across machines.
- *Status.* documented.
- *Enforcement.* Snapshot and report tests.

**H-002.** The same fixture input produces the same report, excluding normalized durations and timestamps.
- *Rationale.* Mutation evidence must be reproducible.
- *Status.* documented.
- *Enforcement.* Repeat-run fixture tests.

**H-003.** Seeded property tests print the seed on failure and can replay it.
- *Rationale.* Agent debugging requires a stable reproducer.
- *Status.* documented.
- *Enforcement.* Property-test policy and future property harness tests.

**H-004.** Parallel worker execution does not affect report order.
- *Rationale.* Performance work must not alter deterministic artifacts.
- *Status.* documented.
- *Enforcement.* Serial-vs-parallel report equivalence tests.

## Fixtures

**H-100.** Each stable mutator has at least one fixture that exercises a killed or compile-error path and at least one fixture that can reveal a survivor.
- *Rationale.* Mutators should prove both candidate generation and result classification.
- *Status.* planned.
- *Enforcement.* Mutator gap registry and fixture tests.

**H-101.** Fixture expectations are explicit files or assertions, not prose.
- *Rationale.* Agents need executable contracts.
- *Status.* documented.
- *Enforcement.* Fixture-system tests.

**H-102.** Fixtures that intentionally produce compile errors label them as expected compile-error outcomes.
- *Rationale.* Compile errors are normal mutant evidence, not invalid mutants.
- *Status.* documented.
- *Enforcement.* Runner classification tests.

## Sandbox and Runner

**H-200.** The patch sandbox applies one mutant at a time and verifies the original text before patching.
- *Rationale.* A stale span must fail safely.
- *Status.* documented.
- *Enforcement.* Sandbox tests.

**H-201.** Sandbox cleanup is verified after every run.
- *Rationale.* Mutation runs must not leave source changes behind.
- *Status.* documented.
- *Enforcement.* Sandbox cleanup tests.

**H-202.** Baseline failure stops mutation execution and records `baseline_failed` as a run-level report status.
- *Rationale.* Mutant results are meaningless when the unmodified project is already failing.
- *Status.* documented.
- *Enforcement.* Runner tests.

**H-203.** Mutant command evidence records original command text, parsed argv, cwd, environment policy, shell flag, exit code, timeout status, stdout/stderr excerpts, and summary. The execution mode is recorded on the enclosing mutation result.
- *Rationale.* Reports must support debugging without full logs.
- *Status.* documented.
- *Enforcement.* Report schema and runner tests.

## Doctests

**H-300.** Doctest extraction order and case IDs are deterministic.
- *Rationale.* Docs are executable contracts.
- *Status.* documented.
- *Enforcement.* Doctest extraction tests.

**H-301.** Doctest output matching normalizes paths, durations, timestamps, and configured nondeterministic fields.
- *Rationale.* Public docs must not be machine-local.
- *Status.* documented.
- *Enforcement.* Doctest snapshot tests.

**H-302.** Doctest mutation experiments remain explicit and do not affect normal `zentinel doctest` behavior.
- *Rationale.* Documentation validation and mutation-aware documentation are separate modes.
- *Status.* documented.
- *Enforcement.* Doctest CLI tests.

## Dogfood and CI

**H-400.** Fixture dogfood starts before source dogfood.
- *Rationale.* zentinel should prove mutator behavior on controlled projects before mutating itself.
- *Status.* documented.
- *Enforcement.* Task order and dogfood tests.

**H-401.** Protected dogfood scope fails on invalid mutants, nondeterministic reports, and protected survivor regressions after gating is enabled.
- *Rationale.* Dogfood should catch tool regressions without turning mutation score into a blunt gate.
- *Status.* documented.
- *Enforcement.* Dogfood CI tasks.

**H-402.** Default CI harness jobs require no live AI provider and no network access after dependencies and Zig are available.
- *Rationale.* Deterministic verification must work offline.
- *Status.* documented.
- *Enforcement.* CI configuration and stub-provider tests.
