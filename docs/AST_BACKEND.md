# AST Backend

The AST backend is zentinel's stable default mutation backend.

## Purpose

The AST backend parses Zig source, identifies syntactic mutation candidates, maps them to source spans, and emits source-text replacements. It is designed to be predictable, debuggable, and suitable for normal CI use.

## Stability Expectation

| Property | Requirement |
| --- | --- |
| Default status | Enabled by default once Phase 1 is complete. |
| Report stability | Stable fields and operator names. |
| Source mapping | Required for every mutant. |
| Zig version coupling | Coupled to latest stable Zig syntax only. |
| Failure mode | Clear diagnostic; no silent candidate loss. |

## Architecture

```text
source file
  -> lexer/parser
  -> AST traversal
  -> candidate recognizers
  -> mutator-specific validation
  -> source span extraction
  -> replacement rendering
  -> shared Mutant model
```

The backend must keep parsing and mutation generation separate:

- parser builds syntax representation
- recognizers find candidate nodes
- mutators validate contexts and replacements
- renderer emits exact source replacement

## Source Mapping Strategy

Every AST mutant must include:

- project-relative path
- byte start and byte end offsets
- 1-based line and column range
- original source text
- replacement source text

Line and column values are for humans. Byte offsets are authoritative for patching.

## Mutation Generation Strategy

The AST backend generates one mutant per operator replacement. It does not combine multiple changes.

Example:

```zig
return a + b;
```

emits:

```json
{
  "operator": "arithmetic_add_sub",
  "original": "+",
  "replacement": "-"
}
```

## Risks

| Risk | Mitigation |
| --- | --- |
| Zig grammar changes | Latest-stable-only policy and version gate. |
| Precedence changes | Renderer tests for each operator. |
| Same-file tests mutated accidentally | AST traversal excludes `test` bodies by default. |
| Formatting churn | Minimal token replacement only. |
| Context-free invalid mutants | Classify compile errors; add semantic filters only with tests. |

## Testing Requirements

AST backend tests must cover:

- every stable operator in `docs/MUTATOR_SPEC.md`
- source span accuracy
- line/column accuracy
- same-file test exclusion
- deterministic candidate ordering
- compile-error classification for `may_fail` operators
- report serialization from generated mutants

## Future Roadmap

AST backend evolution:

1. Phase 1 syntactic operators.
2. Phase 2 Zig-native semantic operators with conservative validation.
3. Phase 3 performance improvements through parsed-file caching.
4. Phase 5 parity tests against ZIR/AIR where semantic mapping overlaps.

The AST backend remains the stable default even after experimental backends exist.
