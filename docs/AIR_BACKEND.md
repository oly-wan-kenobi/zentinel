# AIR Backend

The AIR backend is an experimental backend that aims, eventually, to mutate after semantic analysis. It would be the highest-risk backend because it is closest to compiler internals and farthest from direct source syntax.

## Current scope (honest)

The shipped AIR backend is a **relabel prototype**, not IR analysis. `src/air_backend.zig` derives AIR candidates from the stable AST candidate set and **re-tags** the supported operators with `backend = air` and `backend_stability = experimental`; it does **no AIR lowering and no compiler-internal analysis**. It is reachable **only from `list-mutants --backend air`**; the `run` command always uses the stable AST backend and rejects `--backend` with a clear usage error. The post-semantic-analysis goals below are future work, not current behavior.

## Direction: SEM-1 supersedes expanding this prototype (2026-06)

The "understand resolved types / safety checks / lowered behavior" ambition below was pursued **not** by growing this AIR prototype into a real IR backend, but by the **compiler-oracle semantic filter (SEM-1, `ZIR_IMPROVEMENTS.md` "Beyond ZIR")**. Rationale: AIR is not exposed by `std` (only `Ast`/`Zir` are), so an AIR backend would have to vendor `Sema`/`Air`/`InternPool` — far more fragile than the version-coupled offsets the ZIR work already fought. Using the pinned compiler as a black box gets the type/compile payoff without that accessibility wall.

SEM-1's outcome (see the ledger):
- **SEM-1c shipped** the compile-as-classifier win — the report's `expected_compile` is now the compiler's *actual* verdict for a run mutant, derived for free from the run it already performs (`src/semantic_filter.zig`). This is the "Sema as the type/compile oracle" goal, delivered without IR introspection.
- **SEM-1b (TCE equivalence/dedup filter) was descoped** — a measurement spike found 0 equivalents/0 duplicates over 80 real Debug-mode mutants (the runner compiles at Debug, where the optimizer normalizes nothing), so the equivalent-mutant payoff that motivated post-Sema analysis is ~0 in this pipeline.

This `air_backend.zig` prototype therefore remains a **frozen, opt-in experiment**: it is kept (still compiled, tested, and reachable via `list-mutants --backend air`) but is **not** the path to post-Sema semantics — SEM-1 is. The goals listed below are retained as historical motivation, not an active roadmap for this module.

## Purpose

AIR may eventually allow zentinel to understand:

- resolved types
- safety checks
- lowered error and optional behavior
- optimizer-visible control flow
- mode-specific behavior

This backend is for research and controlled experiments until it proves reliable source mapping.

## Stability Expectation

| Property | Requirement |
| --- | --- |
| Default status | Disabled. |
| Activation | Explicit experimental opt-in only. |
| Source mapping | Required for executable mutants. |
| Result semantics | Must use shared runner and report model; `backend_stability` is `experimental`. |
| User trust | Never present AIR output as stable until promoted by roadmap. |

## Architecture

```text
semantic analysis / AIR data
  -> AIR extraction adapter
  -> typed candidate recognizers
  -> source correlation
  -> source-level patch planner or runner-level variant
  -> shared Mutant model
```

AIR may identify semantic candidates, but the initial execution strategy should still prefer source-level patches when possible. Runner-level IR mutation is not allowed until it has a deterministic sandbox and report story.

The backend targets pinned Zig `0.16.0`; compiler-internal drift is handled by explicit opt-in diagnostics, not by moving version discovery.

## Source Mapping Strategy

AIR mapping must include:

- exact source span for the originating expression
- resolved type metadata when available
- safety mode metadata
- confidence value represented as enum, not probability

Executable AIR mutants require `source_mapping: exact`.

Non-executable AIR diagnostics may use:

```text
none
approximate
exact
```

Only `exact` can enter the normal mutant list.

Non-executable AIR inventories, unsupported mapping notes, and compiler-internal evidence are out-of-report AIR diagnostics. The report v1 schema is closed: it accepts `backend` and `backend_stability`, but report v1 does not define backend-specific diagnostic fields. At CLI runtime these diagnostics are surfaced as stderr `note[...]` lines. The schema-versioned on-disk artifact (`air_backend.diagnosticsToJson` → `zentinel.experimental_backend_diagnostics.v1`, intended under `artifacts/pipeline/<task-id>/experimental-backend-diagnostics/`) is defined and tested but its write is not yet implemented (future pipeline work).

## Mutation Generation Strategy

Initial AIR exploration areas:

- bounds-check-related comparisons
- optional unwrap paths
- error union propagation
- safety-check differences by mode
- integer overflow-sensitive operations

AIR must not invent operator names outside `docs/MUTATOR_SPEC.md` without first updating the spec.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Compiler internal instability | Frequent breakage. | Pinned Zig `0.16.0` and experimental flag. |
| Lost source intent | Reports become untrustworthy. | Exact mapping requirement. |
| Optimizer interaction | Different behavior by mode. | Mode-aware report fields. |
| Duplicate logical mutants | Noise and inflated counts. | Dedupe against AST/ZIR by source span and operator. |
| Hard-to-debug failures | Developer distrust. | Preserve compiler evidence and backend diagnostics. |

## Testing Requirements

AIR tests must cover:

- adapter version guard
- source mapping exactness
- mode metadata propagation
- parity with AST where applicable
- rejection of approximate-only candidates
- deterministic ordering independent of compiler traversal order

## Future Roadmap

1. Diagnostics-only AIR inventory.
2. Exact source mapping proof fixtures.
3. Mode comparison experiments.
4. Typed mutator parity with AST.
5. Stabilization review after multiple deliberate Zig pin updates.

AIR cannot become a default backend until it is as trustworthy as AST for source mapping and report reproducibility.
