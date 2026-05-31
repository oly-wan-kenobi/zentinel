# Roadmap

zentinel development is phased so future agents can build independently without changing the architecture underneath each other. Each phase has a stable outcome, explicit non-goals, and a dogfooding expectation.

## Phase Summary

| Phase | Name | Primary Outcome | Backend |
| --- | --- | --- | --- |
| 0 | Foundation | Repo scaffold, CLI shell, config, fixtures, test harness, doctest conventions, agent pipeline contracts. | None |
| 1 | Minimal Mutation Engine | Stable AST/source mutation with first operators, reports, and normal doctest extraction/execution. | AST |
| 2 | Zig Semantics | Zig-native mutators and executable mutator documentation examples. | AST |
| 3 | Performance | Parallel execution, caching, fail-fast, test impact analysis, doctest cache. | AST |
| 4 | AI-Assisted UX | Explain, suggest, review flows, and advisory doctest assistance. | AST |
| 5 | Experimental Backends | ZIR and AIR backends behind explicit opt-in, with future doctest semantic checks. | AST + ZIR/AIR |
| 6 | Safety Mode Intelligence | Compare results across Zig optimization/safety modes, including mode-aware doctests. | AST + optional IR |
| 7 | Dogfooding Expansion | zentinel mutates and doctests substantial parts of itself in CI. | Stable defaults |

Phase labels describe feature areas. The sequential task queue is the authoritative dependency order, so a phase is not complete until all queued tasks that satisfy that phase's exit criteria are complete. In particular, Phase 1 exit criteria include normal doctest extraction/execution work from the queued doctest lane, even when adjacent mutation-engine tasks have already completed.

## Phase 0: Foundation

Deliver:

- repository structure under tracked implementation, test, script, docs, and task-system paths; `examples/` and `tools/` are added only when a later task owns concrete contents
- `zig build test` wired to project tests
- CLI shell with `help`, `version`, `init`, `init --force`, config-aware init options, and `check`
- config loader and validator
- fixture layout for mutation tests
- deterministic snapshot testing utilities
- task and status workflow for sequential AI agents
- doctest block conventions for future public examples
- AI-agent pipeline architecture, role contracts, handoff contracts, context packets, verification policy, and failure recovery policy

Exit criteria:

- all commands have tests before implementation
- `zig build test` passes from a clean checkout
- `zentinel check` validates config, Zig version policy, paths, test-command syntax, and report output directory without running tests
- config examples are validated by tests
- no mutation execution exists yet
- doctest conventions are documented but not implemented
- future agents can identify required pipeline depth and handoff artifacts without asking a human

## Phase 1: Minimal Mutation Engine

Deliver:

- AST backend as stable default
- source span discovery
- patch sandbox
- `zig test` runner integration
- baseline test verification
- first deterministic mutators:
  - arithmetic swap: `+ <-> -`, `* <-> /`
  - equality swap: `== <-> !=`
  - boundary swap: `>= -> >`, `<= -> <`, `> -> >=`, `< -> <=`
  - logical swap: `and <-> or`
  - boolean literal swap: `true <-> false`
- killed/survived/compile_error/compiler_crash/timeout reports
- `zentinel doctest` extraction and normal execution for CLI/config/report examples

Exit criteria:

- fixture suite proves every operator
- reports are deterministic across repeated runs
- same-file tests are excluded from mutation targets by default
- zentinel can mutate a small internal fixture project
- selected public docs can be validated as executable doctests

## Phase 2: Zig-Native Semantics

Deliver stable AST mutators for:

- optionals and `orelse`
- optional null checks
- error union handling through stable `catch` behavior
- `errdefer`
- integer literal boundaries
- loop and range boundaries

Preview mutators documented in `docs/MUTATOR_SPEC.md`, including allocator failure paths, comptime branch or value mutation, `defer_remove`, and safety or `unreachable` transformations, are design targets and backlog candidates. End-to-end completion excludes preview mutator implementation. They are not required minimum-product implementation unless a later task explicitly names the preview operator in its title or acceptance criteria.

Exit criteria:

- each Phase 2 stable semantic mutator has typed fixture coverage
- compile-error expectations are documented and tested
- equivalent mutant risks are reported, not silently suppressed
- dogfooding reaches selected config and report modules
- stable mutator docs begin using executable `zig before`/`zig after` examples
- preview mutator examples, if added early, remain fixture or documentation coverage only and do not imply default enablement

## Phase 3: Performance

Deliver:

- parallel worker pool
- deterministic scheduling
- incremental cache keyed by source/config/Zig version/test command
- fail-fast behavior for baseline and selected mutant classes
- test impact analysis
- Zig cache reuse strategy
- benchmark suite
- doctest result caching and deterministic repeated-run behavior

Exit criteria:

- repeated runs reuse cache safely
- worker count changes do not change report ordering or IDs
- performance benchmarks have tracked baselines
- dogfooding runs in CI within the concrete budget established by task `052`
- doctest runs fit the same CI determinism and task `052` budget rules

## Phase 4: AI-Assisted UX

Deliver:

- `zentinel explain <mutant-ref>`
- `zentinel suggest <mutant-ref>`
- `zentinel review-tests`
- `zentinel doctest explain <case-ref>`
- `zentinel doctest suggest <doc-path>`
- `zentinel doctest review-snapshot <case-ref>`
- `zentinel doctest suggest-missing [--file <doc-path>]`
- `zentinel doctest explain-survivor <survivor-ref>`
- local/offline model provider interface
- privacy-safe prompt construction
- JSON prompt contracts and response validation
- advisory annotations in reports
- advisory doctest failure, snapshot-review, missing-example, and doctest-survivor flows

Exit criteria:

- deterministic reports are valid without AI configured
- AI output is clearly labeled advisory
- malformed model output cannot alter core results
- offline model flow is documented and tested with a stub provider
- doctest AI subcommands are user-facing CLI surfaces with stub-provider coverage
- AI doctest suggestions are validated as advisory-only outputs

## Phase 5: Experimental ZIR/AIR Backends

Deliver:

- backend selection config
- ZIR candidate generation prototype
- AIR candidate generation prototype
- source mapping diagnostics
- compatibility guards for pinned Zig `0.16.0` internals
- backend parity tests against AST fixtures where applicable
- experimental semantic checks for mutation-aware doctest examples where source mapping is exact

Exit criteria:

- experimental backends require explicit opt-in
- reports identify backend and stability
- backend failures degrade to clear diagnostics, not silent misreports
- AST remains the default and stable path

## Phase 6: Safety Mode Intelligence

Deliver:

- per-mutant execution across configured modes
- mode comparison report
- insights for Debug-only, ReleaseSafe-only, ReleaseFast-only behavior
- safety-check-aware mutation classes

Exit criteria:

- reports distinguish safety-mode effects from test failures
- mode matrix output remains deterministic
- CI can limit modes by config
- doctests that document mode-specific behavior can run mode matrices deterministically

## Phase 7: Dogfooding Expansion

Deliver:

- mutation checks over core zentinel modules
- dogfood thresholds based on survivor review, not score worship
- release gating for deterministic core regressions
- internal survivor triage workflow
- executable docs in CI for CLI, config, report, mutator, and AI contract examples
- archived pipeline artifacts for dogfood tasks, mutation gates, doctest reports, property-test reports, and final verification

Exit criteria:

- zentinel routinely mutates its own core
- dogfood reports are archived as release artifacts
- new mutators are required to survive internal dogfood review before stabilization
- doctest reports and mutation-aware doctest reports are archived as release artifacts

## Release Acceptance

The minimum complete product (`docs/PROJECT_ACCEPTANCE_CRITERIA.md`) is verified by task `060` release acceptance, the final gate after the Phase 7 dogfood hardening (tasks `061`, `062`, `064`, `065`, `066`, `067`, `085`). `scripts/release_acceptance.py` and `test/release_acceptance_test.zig` check the required commands, the 12 stable mutators, text/json/jsonl/junit reports, registered schemas, public-doc doctests, the final dogfood gate evidence under `artifacts/pipeline/085/dogfood/`, network-free CI, advisory-only AI, and the AST-stable-default / experimental-opt-in backend policy from archived deterministic evidence. A release blocker is recorded as a `blocked` acceptance manifest with concrete prerequisite task metadata, never by relaxing these criteria.

## Doctest Adoption Timeline

Doctests become mandatory in stages:

| Stage | Mandatory behavior |
| --- | --- |
| Conventions documented | New public examples must use supported doctest block tags when intended to be executable. |
| Normal doctest command exists | Public CLI/config/report docs changed by a task must include passing doctests. |
| Doctest dogfood exists | CLI, config, report, and AI contract docs must pass doctests in CI. |
| Mutation-aware specs exist | Stable mutator docs must include executable before/after examples. |
| `doctest --mutate` is stable | New stable mutators must pass mutation-aware doctest checks before stabilization. |

See `docs/DOCTEST_ROADMAP.md`.

## Agent Pipeline Roadmap

The pipeline becomes stricter in stages:

| Stage | Required behavior |
| --- | --- |
| Pipeline contracts documented | Tasks include allowed files, forbidden files, TDD instructions, verification expectations, and handoff requirements. |
| Handoff artifacts introduced | After task `041`, each role emits canonical JSON handoff artifacts under `artifacts/pipeline/<task-id>/`, with optional Markdown companion summaries; before task `041`, equivalent handoff fields live in task status or completion summaries. |
| Context packets introduced | Stateless subagents receive bounded packets containing task specs, relevant docs, prior artifacts, constraints, and verification expectations. |
| Verification pipeline automated | Unit, property, doctest, mutation, dogfood, snapshot, performance, and task-system checks run in deterministic order. |
| Mutation gate enforced | Mutation-testable tasks cannot complete until mutation results are classified and survivors are triaged. |
| Pipeline dogfood stable | zentinel uses its own reports and doctests to validate core development tasks in CI. |

See `docs/AGENT_PIPELINE_ARCHITECTURE.md`.

## Release Philosophy

zentinel should release small stable increments:

- commands before engines
- reports before AI
- AST before IR
- deterministic behavior before performance optimization
- dogfooding before broad claims

No phase may weaken the deterministic core contract.
