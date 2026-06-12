# Architecture

zentinel is organized as a deterministic mutation pipeline with optional advisory AI layers on top. The core must be useful offline, reproducible in CI, and independent of any model provider.

## Architecture Shape

The primary architecture is a deterministic pipeline with a functional core.

Ports and adapters are boundary tools, not the system architecture. zentinel uses ports/adapters only where deterministic core behavior crosses a side-effect, presentation, or advisory boundary:

- CLI, CI, and editor surfaces adapt user requests into pipeline commands.
- filesystem, process execution, sandbox workspace, cache storage, and report writers are side-effect adapters.
- AI provider integrations are advisory adapters that consume deterministic artifacts.
- pipeline orchestration coordinates the flow without owning mutation semantics.
- deterministic core modules own source mapping, command parsing, mutant identity, candidate generation, filtering, test-selection rules, result classification, advisory-context validation/redaction, and canonical report data.

This follows ADR-0008. A task that changes these boundaries must update `docs/INTERNAL_API_CONTRACTS.md` and either cite ADR-0008 or add a superseding ADR.

## System Overview

```text
zentinel
├─ CLI
├─ Config
├─ Command Parser
├─ Project Model
├─ Test Discovery
├─ Test Selection
├─ Doctest Engine
├─ Mutation Engine
│  ├─ AST Backend (stable default)
│  └─ ZIR Backend (experimental)
├─ Mutators
├─ Sandbox / Patch Application
├─ Runner
├─ Cache
├─ Reporting
├─ AI Assistance Layer
└─ CI / Editor Integration Surfaces
```

## Deterministic Core Boundary

The deterministic core includes:

- parsing configuration
- parsing configured command strings into argv without a shell
- discovering source files and tests
- extracting, planning, and executing doctests
- generating mutant candidates
- assigning mutant IDs
- applying and reverting mutations
- selecting tests
- planning Zig command argv and classifying executor outcomes
- classifying mutant results as killed, survived, timeout, compile_error, compiler_crash, skipped, or invalid, and run-level baseline failures as baseline_failed
- building machine-readable and human-readable report data
- building cache keys and cache entry data
- validating and redacting advisory AI context before any provider boundary

The deterministic core must not depend on:

- LLM responses
- remote network availability
- AI provider execution
- wall-clock ordering for IDs
- nondeterministic filesystem iteration
- random scheduling decisions without an explicit seed
- CLI command routers, process runners, sandbox workspace managers, cache storage adapters, report writers, or AI provider adapters

## Architecture Boundary Contract

Deterministic core modules must not import adapters.

Every future Zig source file under `src/` must declare its layer with a top-of-file comment:

```zig
// Layer: deterministic_core
```

Allowed layers and forbidden import edges are defined in `docs/INTERNAL_API_CONTRACTS.md`. The validator treats missing layer declarations and deterministic-core imports of side-effect, presentation, pipeline-orchestration, or advisory adapters as architecture drift.

Reviewers must check ownership, not only compile success:

- `runner` executes parsed commands; it does not generate mutants.
- `report` renders deterministic evidence; it does not run commands or invent results.
- `mutators/*` emit exact source spans and replacements; they do not import AI, runners, or report writers.
- `ai/*` consumes deterministic artifacts; it does not write result status, cache keys, source maps, or classifier evidence.
- CLI modules route commands; they do not own mutation semantics.

## AI Boundary

The AI assistance layer may consume deterministic artifacts and produce advisory artifacts. Pure AI context builders, redactors, schema validators, and prompt-envelope validators are allowed in the deterministic core because they are deterministic data-safety gates: they only reject or normalize existing evidence. Provider execution, remote access, model selection, and advisory text generation stay at the advisory-adapter boundary and never feed result classification.

Allowed:

- explain why a survivor matters
- classify a survivor into review labels such as `boundary_missing`
- suggest focused tests
- cluster similar survivors
- review report trends

Forbidden:

- mark a mutant killed or survived
- suppress a mutant automatically
- decide that a mutant is equivalent
- modify source or tests without an explicit developer request
- change cache keys, report evidence, or pass/fail semantics

## Shared Data Model

Every backend emits the same logical `Mutant` model:

```text
Mutant
├─ id: stable deterministic identifier
├─ display_id: report-local compact index, assigned only when rendering a report
├─ backend: ast | zir
├─ backend_stability: stable | experimental
├─ operator: mutation operator name
├─ operator_stability: stable | preview | experimental
├─ file: project-relative source path
├─ span: byte offsets and line/column range
├─ original: exact source text or backend value
├─ replacement: exact replacement text or backend value
├─ context: typed metadata used for reporting and filtering
├─ expected_compile: compiles | may_fail | must_fail
└─ advisory metadata: equivalent risks and optional AI annotations
```

The durable mutant `id` uses the `m_` prefix and this deterministic derivation:

```text
m_ + first_26_chars(lowercase_unpadded_crockford_base32(sha256(canonical_mutant_bytes)))
```

`canonical_mutant_bytes` is UTF-8 text with `\n` separators and this exact field order:

```text
zentinel.mutant.v1
backend_version
project_relative_file
operator
span_start
span_end
original
replacement
```

`span_start` and `span_end` are decimal byte offsets into the original source buffer. The derivation must not include display order, wall-clock time, absolute paths, command output, result duration, result status, or AI output. The resulting durable ID matches `^m_[A-Za-z0-9]+$` and is byte-identical across agents, sessions, and machines for the same content. This mirrors the doctest mutation-entry identity in `docs/DOCTEST_SPEC.md`.

The display ID is stable only within one report after canonical sorting. It is useful for terminal output and short CLI selectors against a selected report, but it is not a durable backend identity and must not be stored in handoffs or AI context as the canonical reference.

`backend_version` is an internal deterministic backend contract string, not a user-facing backend choice. For the stable AST backend under Zig `0.16.0`, `backend_version` is `ast.v1.zig-0.16.0`. ZIR may define an experimental backend version only when its experiment task documents version coupling and mapping semantics.

## Pipeline

1. Load config.
2. Validate Zig version.
3. Build project model from `build.zig`, package paths, and configured targets.
4. Discover eligible source files.
5. Discover tests and baseline commands.
6. Run baseline tests. Report v1 does not support baseline skipping; `baseline_required = false` is reserved until a future cache-proof contract exists.
7. Generate mutants through the selected backend.
8. Filter by include/exclude rules, operator settings, and safety constraints.
9. Select tests for each mutant.
10. Run unmutated preflight for selected commands that were generated after baseline discovery.
11. Apply one mutant in an isolated worktree or patch sandbox.
12. Run selected tests with deterministic timeout and environment.
13. Classify result from process status, compiler output, compiler crash evidence, and test output.
14. Record report entries and cache artifacts.
15. Optionally run AI explanation against the completed deterministic report.

## Module Responsibilities

| Module | Responsibility | Must Not Do |
| --- | --- | --- |
| CLI | Parse commands, route to commands, render concise output. | Own mutation semantics. |
| Config | Load, validate, normalize project settings. | Read source files for mutation. |
| Command Parser | Parse configured command strings into argv and reject shell-only syntax. | Execute processes or silently approximate shell behavior. |
| Project Model | Describe files, targets, packages, and build commands. | Execute mutants. |
| Test Discovery | Locate `test` declarations and test commands. | Decide mutant status. |
| Test Selection | Map mutants to relevant tests using deterministic rules. | Use AI to select correctness. |
| Doctest Engine | Extract executable documentation, run doctest cases, and match normalized output. | Use AI as a doctest oracle. |
| Mutation Engine | Coordinate backend generation and filtering. | Run Zig commands directly. |
| Backend | Produce candidate mutations with source mapping. | Decide killed/survived. |
| Runner | Execute baseline and mutant tests. | Generate mutations. |
| Cache | Store verified artifacts by content key. | Cache advisory AI as core evidence. |
| Reporting | Emit JSON, text, and CI output. | Invent results not present in runner evidence. |
| AI Assistance | Explain and suggest from reports. | Change deterministic result data. |

## Source Mutation Strategy

The stable backend writes patched source text to an isolated mutation workspace. It does not mutate the developer's working tree in place.

Required sandbox properties:

- no permanent source edits after a run
- deterministic patch application
- fast reset between mutants
- clear diagnostics when patch application fails
- support for running `zig test` and `zig build test`

## Doctest Subsystem

Doctests are first-class deterministic core behavior. They validate executable documentation and later support mutation-aware documentation through `zentinel doctest --mutate`.

```text
Doctest Engine
├─ Markdown fence extractor
├─ Block format parser
├─ Case planner
├─ Temporary workspace generator
├─ Zig/CLI/config executor
├─ Output normalizer
├─ Matcher
├─ Doctest reporter
└─ Mutation-aware doctest bridge (future)
```

The doctest subsystem must use the same deterministic boundaries as mutation testing:

- stable case IDs
- stable extraction order
- isolated temporary workspaces
- normalized snapshots
- no AI authority over pass/fail
- no mutation-aware behavior unless `--mutate` is explicit

Doctest architecture and contracts live in:

- `docs/DOCTEST_ARCHITECTURE.md`
- `docs/DOCTEST_SPEC.md`
- `docs/DOCTEST_BLOCK_FORMATS.md`
- `docs/DOCTEST_MUTATION_STRATEGY.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/DOCTEST_ROADMAP.md`

## Error Model

Errors should preserve enough context for CLI and JSON reports:

```text
ZentinelError
├─ code
├─ message
├─ phase
├─ file
├─ span
├─ command
└─ evidence
```

Error messages must be compiler-like: direct, scoped, and actionable.

## Stability Levels

| Stability | Meaning |
| --- | --- |
| stable | Supported for normal use and CI. Behavior changes require migration notes. |
| experimental | Available only behind explicit opt-in. Output may change between releases. |
| internal | Not exposed in config, CLI, or report contracts. |

The AST backend is stable by default. The ZIR backend is experimental: it re-tags the stable AST candidate set with `backend = zir` (binary-operator sites are recognized from real `std.zig.AstGen` ZIR lowering; see `docs/ZIR_BACKEND.md`). It is reachable only through `list-mutants --backend <zir>`; the `run` command always uses the stable AST backend and rejects `--backend` with a clear usage error. Real IR-level analysis is future work, not current behavior.

## Architecture Invariants

- A mutant result is determined only by running selected tests.
- A compile error is a deterministic result category, not an AI judgment.
- Equivalent mutant detection is advisory unless proven by deterministic rules and documented in `MUTATOR_SPEC.md`.
- Canonical reports must be reproducible for the same repository content, Zig version, config, and command after documented observation metadata such as run ID, timestamps, and durations is normalized.
- Test selection may reduce which tests run, but it must never hide a survivor from the final report.
- Dogfooding requirements apply as soon as the relevant subsystem exists.
- Doctest pass/fail is determined only by deterministic extraction, execution, normalization, and matching.
