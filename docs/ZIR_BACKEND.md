# ZIR Backend

The ZIR backend is an experimental backend for exploring mutation at Zig's intermediate representation level before full semantic lowering.

## Purpose

ZIR can expose semantic structure that is difficult to infer from source syntax alone, especially around comptime execution, inferred types, and generic instantiations.

The ZIR backend exists to answer:

- can zentinel identify better semantic mutation points?
- can source mapping remain trustworthy?
- can ZIR candidates map back to the same shared mutant model?

## Stability Expectation

| Property | Requirement |
| --- | --- |
| Default status | Disabled. |
| Activation | Explicit config or CLI opt-in only. |
| Report stability | Experimental backend fields may change, shared result fields may not. |
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

## Source Mapping Strategy

ZIR candidates are executable only when mapped to an exact source span. If a ZIR instruction cannot map to source:

- it may be recorded in backend diagnostics
- it must not become an executable mutant
- it must not affect mutation score or survivor counts

The report must include:

```json
{
  "backend": "zir",
  "stability": "experimental",
  "source_mapping": "exact"
}
```

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
| Zig internals change | Backend breaks between Zig releases. | Latest-stable gate and backend diagnostics. |
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
