# Doctest Roadmap

Doctests become first-class in zentinel through staged adoption. Normal executable documentation comes before mutation-aware documentation.

## Phase Alignment

| Roadmap phase | Doctest work |
| --- | --- |
| Phase 0 | Establish doctest block conventions and require future public docs to use supported tags. |
| Phase 1 | Implement extraction, planning, and non-mutating execution for CLI/config/report docs. |
| Phase 2 | Make mutator specs executable through `zig before`/`zig after` examples. |
| Phase 3 | Add caching, deterministic parallel execution, and doctest runtime budgets. |
| Phase 4 | Add advisory AI flows for doctest failures, missing examples, and snapshot review. |
| Phase 5 | Explore ZIR-backed semantic checks for mutation-aware doctest examples. |
| Phase 6 | Add safety-mode doctest matrices for examples that document mode-specific behavior. |
| Phase 7 | Dogfood doctests across zentinel docs and gate public docs in CI. |

## Stage 0: Conventions

Deliver:

- `docs/DOCTEST_BLOCK_FORMATS.md`
- `docs/DOCTEST_SPEC.md`
- authoring rules requiring executable examples for public features

Exit criteria:

- future agents know how to author executable docs
- docs identify which examples are executable and which are prose-only

## Stage 1: Extraction and Planning

Deliver:

- Markdown fence extractor
- block classifier
- deterministic case planner
- invalid doctest diagnostics
- JSON case inventory output

Exit criteria:

- docs can be scanned without executing code
- case IDs and ordering are stable
- unsupported block formats fail clearly when tagged as doctests

## Stage 2: Normal Execution

Deliver:

- Zig compile-pass execution
- `zig test` execution
- compile-fail execution
- CLI example execution
- config example validation
- text and JSON matching

Exit criteria:

- `zentinel doctest` validates selected docs
- snapshots normalize volatile output
- doctest reports are deterministic

## Stage 3: Doctest Dogfooding

Deliver:

- CLI docs executable
- config docs executable
- report examples executable
- AI prompt contract examples schema-checked

Exit criteria:

- public docs cannot drift silently from implementation
- CI can run doctests without network access

## Stage 4: Mutation-Aware Specs

Deliver:

- mutator spec examples expressed as `zig before`/`zig after`
- transformation validation against AST mutators
- mutation-aware doctest report fields

Exit criteria:

- mutator documentation examples are executable contracts
- transformation docs fail when mutator output drifts

## Stage 5: `doctest --mutate`

Deliver:

- mutate executable doctest snippets
- run doctest assertions against mutants
- report killed/survived documentation mutants
- skip weak examples with deterministic reasons

Exit criteria:

- `zentinel doctest --mutate` works on fixture docs
- survivors point to missing documentation assertions
- AI explanations are optional and advisory

## Mandatory Adoption Points

| Point | Requirement |
| --- | --- |
| After doctest conventions | New public CLI/config/report examples must use supported tags. |
| After normal doctest execution | Public docs changed by a task must include or update doctests. |
| After doctest dogfooding | CLI/config/report docs must pass `zentinel doctest` in CI. |
| After mutation-aware specs | New stable mutators must include executable before/after examples. |
| After `doctest --mutate` | New stable mutator docs must be mutation-checked before stabilization. |

## Long-Term Outcome

zentinel docs become executable specifications:

- CLI docs verify CLI behavior
- config docs verify parser behavior
- report docs verify schema behavior
- mutator docs verify transformations
- AI docs verify prompt/response contracts
- mutation-aware doctests verify example strength
