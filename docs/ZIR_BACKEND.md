# ZIR Backend

The ZIR backend is an experimental backend that aims, eventually, to explore mutation at Zig's intermediate representation level before full semantic lowering.

## Current scope (honest)

The ZIR backend does **real ZIR lowering for every binary-operator mutation** (task 056, Phases 1-3): comparison (`equality_swap`, `comparison_boundary`), short-circuit logical (`logical_and_or`), and arithmetic (`arithmetic_add_sub`, `arithmetic_mul_div`). `src/zir_backend.zig` `fromTree`/`listFromTrees` lowers each source file to ZIR with `std.zig.AstGen.generate` and recognizes mutation sites from the instructions ZIR emits — `cmp_*`, `bool_br_and`/`bool_br_or`, and `add`/`sub`/`mul`/`div` — mapping each back to its exact AST node via the `pl_node.src_node` declaration-relative offset (`expectedAstTag` → `resolveNode`). Candidate metadata is held in exact differential parity with the AST recognizers (`comparison.zig`, `logical.zig`, `arithmetic.zig`) — pinned by the `zir_backend` parity tests, including `arithmetic_*`'s `expected_compile = .may_fail` — so the ZIR candidates are byte-identical to the AST ones in a runtime context, re-tagged `backend = zir`, `backend_stability = experimental`. The **one** in-context refinement ZIR adds is comptime-aware `expected_compile`: a binary-operator site inside a `comptime { ... }` block (located via the ZIR `block_comptime` instructions; see `comptimeBlockSpans`) has its `.compiles` bucket downgraded to `.may_fail`, because comptime evaluation is strict (a swap can surface a *compile* error a runtime context would defer). AstGen-injected operators (for-bounds, array indexing, switch ranges) resolve to no source node and become out-of-report diagnostics, never mutants.

### Scope boundary: ZIR covers binary operators, and only those

The remaining operators are **AST-only by principle**, not a backlog — because ZIR represents them in a form that is worse than the AST, not better:

- **Literal mutations** — `boolean_literal` (`true`/`false`) and `integer_literal_boundary` (number literals) lower to operand **refs** (`Inst.Ref.bool_true`/`.zero`/`.one`/…), never instructions, so there is no instruction to recognize and no recoverable literal span. There is nothing for ZIR to do here; the AST is the correct (lexical) layer.
- **Control-flow / structural mutations** — `error_catch_unreachable` (`catch`), `optional_orelse_unreachable` (`orelse`), `errdefer_remove`, and `loop_boundary` **desugar into multi-instruction patterns** (`is_non_err`/`err_union_code`/`condbr`/blocks). The clean single AST node (`.catch`, `.@"orelse"`, `.@"errdefer"`) is the right recognition layer; reconstructing it from the ZIR shape is strictly harder and more fragile, with no benefit. `optional_null_check` is a `cmp_*` against the `null` ref — lowerable, but with no advantage over the AST's null-token check.

The principle: **ZIR is the right layer for operators that survive as a single instruction (the binary operators) and the wrong layer for literal/lexical and control-flow-structural mutations.** The payoff those would want — types, reachability, equivalent-mutant filtering — is a post-`Sema` (**AIR**) property, not a ZIR one. Each unlowered operator is emitted as an out-of-report diagnostic carrying the specific reason, so a previously-listed operator is never silently dropped.

The ZIR backend has a single code path: `listFromTrees` (real ZIR lowering). The legacy `fromAst` relabel adapter has been retired. It is reachable **only from `list-mutants --backend zir`**; the `run` command always uses the stable AST backend and rejects `--backend` with a clear usage error.

## Purpose

The future ZIR backend could expose semantic structure that is difficult to infer from source syntax alone, especially around comptime execution, inferred types, and generic instantiations. The current prototype takes the first concrete step here — comptime-context-aware `expected_compile` (above), derived from the ZIR `block_comptime` instructions rather than source syntax — but inferred types and generic instantiations remain post-`Sema` (AIR) properties it does not yet expose.

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

The backend targets pinned Zig `0.16.0`. Because the `pl_node.src_node` decoding is coupled to that exact toolchain, `listFromTrees` actively declines (`error.UnsupportedZigVersion`, surfaced as a clear `--backend zir` diagnostic) on any other version — including a same-version nightly or a missing Zig — via `toolchainSupported` (3a), rather than risk silent mis-resolution on a moving release. As a standing cross-check, `differentialOracle` compares the ZIR-recognized binary-operator set against the AST recognizers' set, and `fromTree` audits that the recognized instructions resolve to a bijection over distinct AST nodes, flagging any collision as an out-of-report anomaly (3c).

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
