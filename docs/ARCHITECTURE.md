# Architecture

zentinel is organized as a deterministic mutation pipeline with optional advisory AI layers on top. The core must be useful offline, reproducible in CI, and independent of any model provider.

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
│  ├─ ZIR Backend (experimental)
│  └─ AIR Backend (experimental)
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
- invoking Zig commands
- classifying mutant results as killed, survived, timeout, compile_error, skipped, or invalid, and run-level baseline failures as baseline_failed
- writing machine-readable and human-readable reports
- reading and writing cache entries

The deterministic core must not depend on:

- LLM responses
- remote network availability
- wall-clock ordering for IDs
- nondeterministic filesystem iteration
- random scheduling decisions without an explicit seed

## AI Boundary

The AI assistance layer may consume deterministic artifacts and produce advisory artifacts.

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
- modify source or tests without an explicit developer or agent task
- change cache keys, report evidence, or pass/fail semantics

## Shared Data Model

Every backend emits the same logical `Mutant` model:

```text
Mutant
├─ id: stable deterministic identifier
├─ display_id: report-local compact index, assigned only when rendering a report
├─ backend: ast | zir | air
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

IDs are derived from stable content:

```text
hash(project_relative_file, operator, span_start, span_end, original, replacement, backend_version)
```

The display ID is stable only within one report after canonical sorting. It is useful for terminal output and short CLI selectors against a selected report, but it is not a durable backend identity and must not be stored in handoffs or AI context as the canonical reference.

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
10. Apply one mutant in an isolated worktree or patch sandbox.
11. Run selected tests with deterministic timeout and environment.
12. Classify result from process status, compiler output, and test output.
13. Record report entries and cache artifacts.
14. Optionally run AI explanation against the completed deterministic report.

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

The AST backend is stable by default. ZIR and AIR backends are experimental until their source mapping, version coupling, and semantic behavior are proven.

## Architecture Invariants

- A mutant result is determined only by running selected tests.
- A compile error is a deterministic result category, not an AI judgment.
- Equivalent mutant detection is advisory unless proven by deterministic rules and documented in `MUTATOR_SPEC.md`.
- Canonical reports must be reproducible for the same repository content, Zig version, config, and command after documented observation metadata such as run ID, timestamps, and durations is normalized.
- Test selection may reduce which tests run, but it must never hide a survivor from the final report.
- Dogfooding requirements apply as soon as the relevant subsystem exists.
- Doctest pass/fail is determined only by deterministic extraction, execution, normalization, and matching.
