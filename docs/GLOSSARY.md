# Glossary

This document defines canonical zentinel terminology. Agents must use these terms in docs, task files, reports, comments, and handoff artifacts instead of inventing synonyms.

## How This Document Works

Terms are lowercase unless they name a concrete backend, command, schema, status, or file.

When a new concept becomes part of the public contract, add it here before using it broadly in specs or task handoffs. Do not create a synonym when an existing term is close enough.

## Terms

**Advisory AI**: Optional AI behavior that explains, clusters, or suggests from deterministic evidence. Advisory AI never determines mutation correctness.

**AI context packet**: A bounded, schema-versioned payload sent to an AI provider. Mutation AI context is governed by `docs/AI_CONTEXT_SCHEMA.md`; doctest AI context is governed by `docs/DOCTEST_AI_INTEGRATION.md`. Both contain only privacy-filtered deterministic evidence allowed by their registered schema.

**AST backend**: The stable default backend that generates mutants from Zig source syntax and exact source spans.

**Backend**: A component that discovers mutation candidates and emits the shared `Mutant` model. Valid backend names are `ast`, `zir`, and `air`.

**Baseline**: The test command result collected before any mutant is applied. A failed baseline blocks mutation execution.

**Candidate**: A potential mutation before it is filtered, assigned a stable ID, and executed as a mutant.

**Canonical order**: The deterministic sort order for mutants: file, byte start, byte end, operator, replacement, backend.

**Compile error**: A deterministic mutant result where the patched project failed to compile before tests executed.

**Compiler crash**: A deterministic mutant result where the Zig compiler process crashes, panics, or terminates abnormally while compiling a syntactically valid mutant. It is distinct from `compile_error` and `invalid`.

**Deterministic core**: The part of zentinel that parses config, discovers files and tests, generates mutants, applies patches, runs commands, classifies results, writes reports, and manages cache entries without AI authority or remote services.

**Display ID**: A compact per-report mutant index derived from canonical order. It is useful for humans but not durable across changed candidate sets.

**Dogfood**: A zentinel run against zentinel fixtures or zentinel source modules.

**Doctest**: An executable documentation example extracted, normalized, run, and matched by zentinel.

**Doctest case ID**: A durable deterministic ID for one extracted doctest case, formatted with the `dt_` prefix. It is derived from stable case content and grouping metadata, not from display-only line numbers. Duplicate unlabeled identical cases in one file are invalid instead of receiving hidden occurrence-based IDs.

**Doctest case ref**: A CLI selector for one doctest case. It may be a durable doctest case ID or a source ref such as `docs/CLI_SPEC.md:47[:label]` resolved against the current extraction or selected doctest report. Source refs resolve only against the case anchor line, not secondary expectation blocks, and are not durable handoff identifiers.

**Doctest survivor ref**: A durable selector for one survived mutation-aware doctest entry, formatted with the `ds_` prefix. It is derived from stable doctest case ID, shared mutant ID, operator, documentation path, source ref, and normalized mutated diff. It is scoped to survived documentation mutants in `zentinel doctest --mutate` reports and is consumed by `zentinel doctest explain-survivor`.

**Equivalent risk**: Metadata saying a mutant may be semantically equivalent or may require a stronger test to distinguish. It is not a reason to suppress the mutant unless a deterministic equivalent filter is documented and tested.

**Experimental backend**: A backend available only behind explicit opt-in. ZIR and AIR are experimental until promoted by docs, tests, and release criteria.

**Fixture**: A small Zig project or source file designed to exercise one behavior or mutator contract.

**Gap registry**: A committed machine-readable file under `tests/coverage-gaps/` that maps docs requirements to tests or documents uncovered work.

**Invalid mutant**: A zentinel bug where a backend or mutator emits malformed source, an out-of-range span, or a candidate that violates its documented contract.

**Killed**: A mutant result where selected tests fail after the baseline passed.

**Mutant**: A single source change with stable metadata, an operator, exact span, replacement text, execution evidence, and result status.

**Mutation sandbox**: An isolated worktree or temporary workspace where one mutant is applied and tested without modifying the developer's source tree in place.

**Mutator**: A named operator that transforms a specific Zig syntax or semantic pattern, such as `comparison_boundary`.

**Oracle**: A source of truth for pass/fail or kill/survive classification. In zentinel, only deterministic command evidence is an oracle. AI is never an oracle.

**Preview mutator**: A mutator documented in `docs/MUTATOR_SPEC.md` but not enabled by default.

**Protected dogfood scope**: The subset of zentinel dogfood runs whose invalid mutants, nondeterminism, or survivor regressions block completion once dogfood gating exists.

**Report**: A deterministic artifact in text, JSON, JSONL, or JUnit format. JSON is the canonical machine-readable form.

**Schema version**: A stable string such as `zentinel.report.v1` that names the contract a machine-readable artifact follows.

**Selected tests**: The deterministic test command or subset chosen for a mutant.

**Stable backend**: A backend enabled for normal CI use and public reports. The AST backend is the stable default.

**Survived**: A mutant result where selected tests passed after the mutant was applied.

**Task system**: The queue and status files under `tasks/` plus `scripts/validate_task_system.py`.

**Timeout**: A deterministic result where a command exceeded the configured timeout.

**ZIR backend**: An experimental backend that may inspect Zig IR when stable, public APIs make that safe.

**AIR backend**: An experimental backend that may inspect lower-level Zig IR when stable, public APIs make that safe.
