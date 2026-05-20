# AIR Backend

The AIR backend is an experimental backend for mutation after semantic analysis. It is the highest-risk backend because it is closest to compiler internals and farthest from direct source syntax.

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
| Result semantics | Must use shared runner and report model. |
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
| Compiler internal instability | Frequent breakage. | Latest-stable-only and experimental flag. |
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
5. Stabilization review after multiple latest-stable Zig releases.

AIR cannot become a default backend until it is as trustworthy as AST for source mapping and report reproducibility.
