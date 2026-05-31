# Project Acceptance Criteria

This document defines what "zentinel is implemented end to end" means for autonomous agents.

## Minimum Complete Product

zentinel is end-to-end complete when a developer can:

1. Run `zentinel init`.
2. Run `zentinel check`.
3. Run `zentinel list-mutants`.
4. Run `zentinel run`.
5. Read deterministic text and JSON reports.
6. See killed, survived, compile_error, compiler_crash, timeout, skipped, and invalid outcomes represented correctly.
7. Use Phase 1 stable AST mutators.
8. Use Phase 2 stable Zig-semantic mutators documented in `docs/MUTATOR_SPEC.md`.
9. Run fixture dogfood.
10. Run selected production-source dogfood.
11. Run CI without network-only dependencies.
12. Use AI explanation/suggestion commands with the stub provider and a local provider interface.
13. Run `zentinel doctest` against public executable docs.
14. Use `zentinel doctest explain`, `zentinel doctest suggest`, `zentinel doctest review-snapshot`, and `zentinel doctest suggest-missing` with the stub provider.
15. Run experimental or stabilized `zentinel doctest --mutate` against fixture documentation when the roadmap reaches mutation-aware doctests.
16. Use `zentinel doctest explain-survivor` with the stub provider after mutation-aware doctest reports are stabilized.

## Required Commands

| Command | Required behavior |
| --- | --- |
| `zentinel --help` | Deterministic help text. |
| `zentinel version` | zentinel version and Zig policy status. |
| `zentinel init` | Writes default config without experimental backends or AI. |
| `zentinel check` | Validates config, Zig version, paths, and commands. |
| `zentinel list-mutants` | Lists candidates without running tests. |
| `zentinel run` | Runs baseline, mutants, and reports results. |
| `zentinel doctest` | Extracts and validates executable documentation examples. |
| `zentinel doctest explain` | Produces advisory AI explanation for a doctest case from a selected doctest report. |
| `zentinel doctest suggest` | Produces advisory executable-example suggestions for a documentation path. |
| `zentinel doctest review-snapshot` | Produces advisory AI review for normalized snapshot differences in a selected doctest report case. |
| `zentinel doctest suggest-missing` | Produces advisory missing-doctest suggestions from deterministic public-docs metadata. |
| `zentinel doctest explain-survivor` | Produces advisory AI explanation for a mutation-aware doctest survivor. |
| `zentinel explain` | Produces advisory AI explanation from a report. |
| `zentinel suggest` | Produces advisory test suggestions from a report. |
| `zentinel review-tests` | Produces advisory survivor clusters from a report. |

## Required Mutators

Stable completion requires:

- `arithmetic_add_sub`
- `arithmetic_mul_div`
- `equality_swap`
- `comparison_boundary`
- `logical_and_or`
- `boolean_literal`
- `optional_orelse_unreachable`
- `optional_null_check`
- `error_catch_unreachable`
- `errdefer_remove`
- `integer_literal_boundary`
- `loop_boundary`

Preview mutators may exist but are not required for the minimum complete product. End-to-end completion excludes preview mutator implementation. A preview operator becomes implementation scope only when a future task explicitly names that operator in its title or acceptance criteria.

## Required Reports

Required formats:

- text
- json
- jsonl

JUnit is required before CI gating and must follow the diagnostic mapping in `docs/REPORT_FORMAT.md`.

JSON reports must satisfy `schemas/report.v1.schema.json`.

## Required Dogfooding

End-to-end completion requires:

- fixture dogfood command
- selected internal module dogfood command
- archived dogfood JSON report under `artifacts/pipeline/<task-id>/dogfood/`
- deterministic repeated dogfood report comparison
- no invalid mutants in stable dogfood scope

Final dogfood reports are archived under `artifacts/pipeline/<task-id>/dogfood/` before release acceptance.

Task `085` is the final release dogfood gate that runs before task `060` release acceptance, as the `release_dogfood_gate` stage in `scripts/ci.sh` (`scripts/release_dogfood_gate.py`). It requires a release-evidence manifest whose fixture, internal-module, public-doc-doctest, mutation-aware-doctest, doctest-survivor-AI, pipeline-artifact, and failure-recovery sub-gates all passed with archived or test-verified evidence; archived deterministic dogfood reports under `artifacts/pipeline/085/dogfood/` whose repeated runs normalize identically; no invalid mutants in protected scope; and every protected-scope survivor fixed by a test or recorded with deterministic equivalent-risk review evidence. Release acceptance verifies the hardened system from this complete dogfood evidence rather than the initial advisory CI wiring.

Dogfood gating must focus on deterministic regressions and reviewed survivor changes, not a single global mutation score.

## Required CI

CI must run:

```bash
scripts/ci.sh
```

The in-repository CI script must include:

```bash
python3 scripts/validate_task_system.py
zig version
zig build test
```

Once mutation execution exists, CI must also run fixture dogfood.

Default CI must not require:

- remote AI providers
- network access after dependencies are available
- experimental ZIR/AIR backends

## Required Performance Baseline

Before claiming performance completion:

- serial and parallel reports must be equivalent except durations
- cached and uncached reports must be equivalent except `diagnostics.cache` and durations
- benchmark output must be machine-readable
- fixture dogfood runtime must fit the documented budget for the repository's CI environment

## Required AI Completion

AI completion requires:

- stub provider
- local provider interface
- privacy redaction tests
- response schema validation
- malformed response rejection
- no ability for AI to alter deterministic result fields
- user-facing doctest AI subcommands with stub-provider tests

Remote providers are optional.

## Required Doctest Completion

Doctest completion requires:

- block parsing for all formats in `docs/DOCTEST_BLOCK_FORMATS.md`
- deterministic extraction and case IDs
- normal execution for Zig, CLI, config, text, JSON, and compile-fail cases
- stable normalized snapshots
- doctest reports with deterministic ordering
- CLI/config/report docs dogfooded through `zentinel doctest`
- mutator docs expressed through executable `zig before` and `zig after` examples
- mutation-aware doctest fixture experiments before stabilization
- doctest AI suggestions and explanations remain advisory and separate from deterministic doctest reports

## Release Gate

A release candidate is acceptable only when:

- all task metadata validates
- governance docs, ADR index, and gap registries validate
- all tests pass
- schemas validate generated reports
- docs match public CLI/config/report behavior
- dogfood reports are generated
- unsupported Zig versions fail clearly
- AST backend remains stable default
- experimental backends are opt-in only

## Release Acceptance Verification

Task `060` is the final release acceptance gate. `scripts/release_acceptance.py` verifies this document's criteria from archived, deterministic evidence — required commands, the 12 stable mutators, text/json/jsonl/junit reports, registered schemas, public-doc doctests (task `066`), the final dogfood gate evidence (task `085`, `artifacts/pipeline/085/dogfood/`), network-free CI, advisory-only AI, and the AST-stable-default / experimental-opt-in backend policy — and exits non-zero with the offending criteria if any are unmet. `test/release_acceptance_test.zig` is the executable contract: a release blocker must be recorded as a `blocked` acceptance manifest with concrete prerequisite task metadata (`test/fixtures/release/valid/acceptance.json` is the consistent-pass form; the `invalid/acceptance_*.json` fixtures show that an unmet criterion or an ignored blocker cannot be hidden behind a passing status). Implementing missing behavior or relaxing these criteria to fit a gap is out of scope for this gate.
