# ZIR Backend

The ZIR backend is an experimental backend that aims, eventually, to explore mutation at Zig's intermediate representation level before full semantic lowering.

## Current scope (honest)

The ZIR backend now does **real ZIR lowering for comparison operators** (task 056, Phase 1). `src/zir_backend.zig` `fromTree`/`listFromTrees` lowers each source file to ZIR with `std.zig.AstGen.generate` and recognizes comparison mutation sites (`equality_swap`, `comparison_boundary`) from the `cmp_*` instructions, mapping each back to its exact AST comparison node via the `pl_node.src_node` declaration-relative offset. Candidate metadata is held in exact differential parity with the AST recognizer (`src/mutators/comparison.zig`) — pinned by the `zir_backend` parity test — so the ZIR candidates are byte-identical to the AST ones, re-tagged `backend = zir`, `backend_stability = experimental`.

What is **not** yet ZIR-lowered: every non-comparison operator (arithmetic, logical, boolean, optional, error-path, integer/loop boundary — Phases 2-3) and every AstGen-injected comparison (for-bounds, switch ranges, which have no source operator) becomes an **out-of-report diagnostic**, never an executable mutant — so a previously-listed operator is never silently dropped. The legacy `fromAst` relabel adapter remains for reference and is exercised by unit tests, but the `list-mutants --backend zir` CLI path uses the real `listFromTrees`. It is reachable **only from `list-mutants --backend zir`**; the `run` command always uses the stable AST backend and rejects `--backend` with a clear usage error. ZIR introspection is pre-`Sema`, so it does not yet provide types or reachability filtering (that is the AIR backend's future role).

## Purpose

The future ZIR backend could expose semantic structure that is difficult to infer from source syntax alone, especially around comptime execution, inferred types, and generic instantiations. The current prototype does not yet do this.

The ZIR backend exists to answer:

- can zentinel identify better semantic mutation points?
- can source mapping remain trustworthy?
- can ZIR candidates map back to the same shared mutant model?

## Stability Expectation

| Property | Requirement |
| --- | --- |
| Default status | Disabled. |
| Activation | Explicit config or CLI opt-in only. |
| Report stability | Shared report v1 fields stay schema-valid; `backend_stability` is `experimental`. |
| Source mapping | Required before a candidate can be executed. |
| Failure mode | Backend diagnostic and fallback to no ZIR candidates. |

## Architecture

```text
Zig compiler frontend data
  -> ZIR extraction adapter
  -> semantic candidate recognizers
  -> source location mapper
  -> source replacement planner
  -> shared Mutant model
```

The ZIR backend must not bypass the shared runner or reporter.

The backend targets pinned Zig `0.16.0`; compiler-internal drift is handled by explicit opt-in diagnostics, not by looking up a moving stable release.

## Source Mapping Strategy

ZIR candidates are executable only when mapped to an exact source span. If a ZIR instruction cannot map to source:

- it may be recorded in out-of-report backend diagnostics
- it must not become an executable mutant
- it must not affect mutation score or survivor counts

The report must include only the closed report v1 backend fields:

```json
{
  "backend": "zir",
  "backend_stability": "experimental"
}
```

The report v1 schema is closed. It accepts `backend` and `backend_stability`, but report v1 does not define backend-specific diagnostic fields. Source-mapping inventories, unsupported-instruction notes, and compiler-internal evidence are out-of-report backend diagnostics until a future schema task adds a namespaced field. At CLI runtime these diagnostics are surfaced as stderr `note[...]` lines. The schema-versioned on-disk artifact (`zir_backend.diagnosticsToJson` → `zentinel.experimental_backend_diagnostics.v1`, intended under `artifacts/pipeline/<task-id>/experimental-backend-diagnostics/`) is defined and tested but its write is not yet implemented (future pipeline work).

## Mutation Generation Strategy

Initial ZIR candidates should focus on semantics with clear source equivalents:

- comptime branch conditions
- optional null checks
- error propagation forms
- integer constants used in type-level calculations

ZIR must emit the same operator names defined in `docs/MUTATOR_SPEC.md` when equivalent to AST operators.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Zig internals change | Backend breaks between Zig releases. | Pinned Zig `0.16.0` gate and out-of-report backend diagnostics. |
| Poor source mapping | Misleading reports. | Require exact mapping for executable mutants. |
| Generic instantiation duplication | Duplicate logical mutants. | Stable dedupe keys using source span and operator. |
| Inactive comptime branch behavior | Compile errors surprise users. | `expected_compile: may_fail` and fixture coverage. |

## Testing Requirements

ZIR tests must include:

- version gate tests
- exact source mapping tests
- parity tests with AST for overlapping operators
- generic function fixture
- comptime branch fixture
- diagnostic output for unmapped instructions

Live compiler-internal tests may be isolated from the default suite until the backend is stabilized, but deterministic adapter tests must run by default.

## Future Roadmap

1. Add backend adapter behind feature flag.
2. Emit diagnostics-only candidate inventory.
3. Enable exact-mapped candidates in fixtures.
4. Compare with AST candidates for duplicate detection.
5. Stabilize only if source mapping and version coupling are acceptable.
