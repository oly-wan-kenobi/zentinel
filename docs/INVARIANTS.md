# Invariants

This document is the authoritative list of properties that must hold across zentinel's deterministic core, task system, reports, and AI boundaries.

## How This Document Works

Invariant numbers are stable and never reused. If an invariant is retired, mark it `[retired]` and leave its number in place.

Every invariant has:

- a stable number
- a single declarative statement
- a rationale
- a status
- an enforcement mechanism
- a failure mode

Statuses:

- `planned`: the invariant is intended but not yet mechanically checked.
- `documented`: the invariant is captured in specs and task requirements.
- `tested`: tests or fixtures exercise the invariant.
- `enforced`: the validator, schema, build, type system, or CI blocks violations.

When code, tests, or docs cite an invariant, use the exact number, for example:

```zig
// I-003: reports use canonical mutant order.
```

## Deterministic Core

**I-001.** A mutant result is determined only by deterministic command evidence.
- *Rationale.* Kill, survive, compile-error, compiler-crash, timeout, and invalid status must be reproducible and auditable.
- *Status.* documented.
- *Enforcement.* `docs/ARCHITECTURE.md`, `docs/MUTATOR_SPEC.md`, `docs/TDD_POLICY.md`, and future runner tests.
- *Failure mode.* AI or heuristics override actual test evidence, making reports untrustworthy.

**I-002.** The same repository content, config, Zig version, backend, safety mode, and command produce the same candidate set and stable mutant IDs.
- *Rationale.* Reports, cache keys, and dogfood comparisons depend on reproducibility.
- *Status.* documented.
- *Enforcement.* Candidate-ordering and cache-key tests in future tasks.
- *Failure mode.* Repeated runs cannot be compared and cache entries become unsafe.

**I-003.** Reports sort mutants by canonical order before assigning display IDs and summary counts.
- *Rationale.* Parallelism and filesystem traversal must not change report meaning.
- *Status.* documented.
- *Enforcement.* Report snapshot and property tests.
- *Failure mode.* A run with the same inputs produces different display IDs or JSON ordering.

**I-004.** Advisory AI never writes or changes deterministic result fields.
- *Rationale.* AI output is optional, provider-dependent, and not a correctness oracle.
- *Status.* documented.
- *Enforcement.* AI schema tests and report contract tests.
- *Failure mode.* Remote text changes whether a mutant is killed, survived, skipped, or invalid.

**I-005.** AST is the stable default backend; ZIR and AIR are experimental opt-in backends.
- *Rationale.* Stable behavior must not depend on compiler-internal surfaces until source mapping and version coupling are proven.
- *Status.* documented.
- *Enforcement.* Config validation tests and backend selection tests.
- *Failure mode.* Default runs become version-fragile or emit unstable source spans.

**I-006.** zentinel supports exactly Zig `0.16.0` for this zentinel version.
- *Rationale.* Supporting multiple Zig versions multiplies parser, semantic, and fixture ambiguity; pinning one version keeps autonomous implementation reproducible.
- *Status.* documented.
- *Enforcement.* Zig version validation tests and ADR-0007.
- *Failure mode.* Agents implement compatibility branches that are not tested or documented.

## Mutation and Sandbox

**I-007.** zentinel never permanently mutates the user's working tree during a run.
- *Rationale.* Mutation testing must be reversible and safe in developer and CI workspaces.
- *Status.* documented.
- *Enforcement.* Sandbox tests and dogfood runs.
- *Failure mode.* A failed run leaves source files changed.

**I-008.** Applying a mutant validates that the source at the recorded span exactly matches the mutant's `original` text.
- *Rationale.* A stale span or changed file must not receive a wrong patch.
- *Status.* documented.
- *Enforcement.* Patch sandbox tests.
- *Failure mode.* zentinel tests a mutation different from the reported mutant.

**I-009.** Zig `test` declaration bodies are excluded from normal mutation targets by default.
- *Rationale.* Mutating tests measures test fragility instead of production behavior.
- *Status.* documented.
- *Enforcement.* AST traversal fixture tests.
- *Failure mode.* Reports include mutants whose survival says nothing about protected production behavior.

**I-010.** `compile_error` is a normal deterministic result for syntactically valid mutants that fail Zig compilation.
- *Rationale.* Some meaningful Zig mutations expose type, comptime, or safety-mode boundaries by not compiling.
- *Status.* documented.
- *Enforcement.* Runner classification tests.
- *Failure mode.* Valid candidates are mislabeled as zentinel bugs.

**I-011.** `invalid` is reserved for zentinel contract violations, malformed patches, or out-of-range spans.
- *Rationale.* Invalid mutants are tool defects and must not be mixed with normal compile errors.
- *Status.* documented.
- *Enforcement.* Mutator contract tests and sandbox tests.
- *Failure mode.* Tool bugs are hidden inside ordinary mutation outcomes.

**I-021.** `compiler_crash` is reserved for abnormal Zig compiler termination while compiling a syntactically valid mutant.
- *Rationale.* Compiler panics and crashes are neither normal type-checking failures nor zentinel patch defects, and they need separate evidence for triage.
- *Status.* documented.
- *Enforcement.* Runner classification tests.
- *Failure mode.* Compiler defects are hidden as `compile_error`, or zentinel tool defects are hidden as compiler crashes.

**I-012.** Test selection may reduce execution cost, but it must never hide an executed mutant from the final report.
- *Rationale.* The report is the audit trail for every generated and filtered candidate.
- *Status.* documented.
- *Enforcement.* Test-selection and report tests.
- *Failure mode.* Survivors disappear because a selection strategy skipped them silently.

## Reports, Cache, and Schemas

**I-013.** Cache keys include every deterministic input that can affect candidates, selected tests, execution, or report output.
- *Rationale.* Reusing stale results is worse than not caching.
- *Status.* documented.
- *Enforcement.* Cache-key property tests.
- *Failure mode.* zentinel reports a result from incompatible source, config, Zig version, backend, safety mode, or command inputs.

**I-014.** Public machine-readable artifacts emit the documented schema version exactly.
- *Rationale.* Agents and integrations need stable parse contracts.
- *Status.* documented, enforced for registry presence.
- *Enforcement.* `docs/SCHEMA_REGISTRY.md`, JSON schemas, and `scripts/validate_task_system.py`.
- *Failure mode.* A report or handoff cannot be safely consumed by future agents.

**I-015.** Snapshot outputs normalize absolute paths, durations, timestamps, and nondeterministic ordering.
- *Rationale.* Snapshots are tests only if they are stable across machines.
- *Status.* documented.
- *Enforcement.* Snapshot tests and review.
- *Failure mode.* CI or dogfood fails for machine-local reasons.

**I-016.** Doctest case IDs and extraction order are deterministic.
- *Rationale.* Public docs become executable contracts and must not drift by parser traversal order.
- *Status.* documented.
- *Enforcement.* Doctest parser and extraction tests.
- *Failure mode.* Documentation test reports change without doc changes.

## Task System and Agent Workflow

**I-017.** At most one task is active pending completion at any time.
- *Rationale.* Sequential autonomous work needs one clear owner and scope.
- *Status.* enforced.
- *Enforcement.* `scripts/validate_task_system.py`.
- *Failure mode.* Two agents make conflicting scope and status changes.

**I-018.** Queue Markdown, queue JSON, status Markdown, and status JSON stay synchronized.
- *Rationale.* Humans and machines must see the same task state.
- *Status.* enforced.
- *Enforcement.* `scripts/validate_task_system.py`.
- *Failure mode.* Agents execute the wrong task or modify forbidden files.

**I-019.** Behavior changes start with failing evidence before implementation.
- *Rationale.* Tests specify intended behavior and keep agents from validating their own assumptions after the fact.
- *Status.* documented.
- *Enforcement.* Task files, handoffs, and reviewer/verifier checks. Current machine checks verify required evidence fields and role handoffs, but do not independently prove chronology until pipeline artifact validation covers role timestamps.
- *Failure mode.* Implementation and tests encode the same unreviewed mistake.

**I-020.** Follow-up implementation work is captured as concrete task metadata, not prose-only notes.
- *Rationale.* Autonomous agents need actionable queue entries.
- *Status.* enforced.
- *Enforcement.* `scripts/validate_task_system.py` rejects prose-only follow-up bullets unless they explicitly state no predefined follow-up exists, and validates referenced task files.
- *Failure mode.* Required work is lost between sessions.
