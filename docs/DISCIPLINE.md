# Discipline

This document defines engineering rules that protect zentinel's invariants. Style rules describe how artifacts look; discipline rules describe what agents must not do because it would threaten correctness, determinism, safety, or autonomous continuity.

## How This Document Works

Rules are numbered `D-NNN`. Numbers are stable and may be cited in task files, handoffs, reviews, and ADRs.

Each rule is binding even before it is fully machine-enforced. When a rule is not yet enforced by tooling, reviewers and agents must still follow it.

## 1. Determinism

**D-001.** Filesystem traversal that affects candidates, tests, reports, snapshots, cache keys, or doctest IDs must be sorted before use.

**D-002.** Map or hash-table iteration order must not affect deterministic output. Convert to a sorted list before deriving IDs, reports, or cache keys.

**D-003.** Wall-clock time must not appear in stable IDs, cache keys, candidate ordering, selected-test ordering, or snapshot output.

**D-004.** Randomness is forbidden in default deterministic behavior unless the seed is explicit, recorded, and replayable.

**D-005.** Paths in reports and snapshots are project-relative and use `/` separators.

**D-006.** Parallel execution must preserve canonical mutant order in all reports.

## 2. Mutation Correctness

**D-100.** Runner evidence is the only authority for killed, survived, compile_error, timeout, skipped, invalid, and run-level baseline_failed statuses.

**D-101.** AI output must not classify mutation correctness, decide equivalence, suppress mutants, or alter deterministic report fields.

**D-102.** Mutators must emit exact source spans and replacement text. Approximate source mapping is forbidden in stable paths.

**D-103.** A mutator may not silently drop a candidate because it might be equivalent.

**D-104.** `compile_error` and `invalid` must remain distinct. A Zig compile failure from a syntactically valid mutant is not an invalid mutant.

**D-105.** Code inside Zig `test` declarations is not a normal mutation target. Any test-mutation experiment must be explicit and labeled.

**D-106.** A single mutant contains one source change unless a future ADR changes the shared mutant model.

## 3. Sandbox and Runner

**D-200.** zentinel must not patch the user's working tree in place during normal mutation runs.

**D-201.** Patch application must verify that the target span still contains the recorded `original` text.

**D-202.** Sandbox cleanup failures must be reported. They must not be hidden behind a successful mutation result.

**D-203.** Every command result used as evidence records original command text, parsed argv, cwd, environment policy, shell usage, phase, exit status, timeout status, and stdout/stderr summary.

**D-204.** Baseline failure blocks mutant execution unless a task explicitly tests baseline-failure reporting.

**D-205.** Timeouts are deterministic classifications. Retrying a timed-out command to obtain a different result is forbidden unless the active task is investigating flakiness.

## 4. Error and Report Contracts

**D-300.** Public error codes are stable once they appear in docs, reports, or snapshots.

**D-301.** Do not swallow Zig command failures. Propagate or record them as structured evidence.

**D-302.** Error messages must be direct, scoped, and actionable. Generic `internal error` text is allowed only with a stable internal error code and evidence.

**D-303.** JSON report writers must emit the documented `schema_version` exactly.

**D-304.** Advisory fields may grow only under advisory namespaces such as `advisory.ai`; deterministic fields require schema review.

## 5. Testing

**D-400.** Behavior changes require failing tests, fixtures, snapshots, doctests, or contract cases before implementation.

**D-401.** Implementers must not weaken, skip, delete, or rebaseline approved tests to make code pass.

**D-402.** Snapshot updates require semantic review. Bulk snapshot regeneration without inspection is forbidden.

**D-403.** Default tests must not call live AI providers, require network access, or depend on machine-local absolute paths.

**D-404.** Property tests that use generated data must use explicit seeds and print failing seeds.

**D-405.** Tests should assert observable behavior at CLI, report, schema, fixture, or public API boundaries unless the active task is explicitly a structural guardrail.

**D-406.** A structural guardrail test must name the future violation that would make it fail.

## 6. Dependencies and Experimental Surfaces

**D-500.** New dependencies follow `docs/DEPENDENCY_POLICY.md` and must be task-scoped, pinned, and tested for failure behavior when relevant.

**D-501.** Remote services must not be required for default CI, deterministic reports, or task-system validation.

**D-600.** The AST backend remains the default stable backend unless a future ADR supersedes that decision.

**D-601.** ZIR and AIR code paths must remain opt-in and clearly labeled experimental.

**D-602.** Experimental backend failures must not fail stable AST jobs unless the active task explicitly changes promotion status.

## 7. Agent and Task Discipline

**D-700.** Agents must respect the active task's allowed and forbidden files unless direct user instructions deliberately change scope.

**D-701.** Task queue and status state must validate before task completion.

**D-702.** Follow-up implementation work must be captured in task metadata.

**D-703.** Handoff artifacts must distinguish evidence from inference and must include failed or skipped commands with reasons.

**D-704.** Agents must not use chat history as the durable state for task decisions.
