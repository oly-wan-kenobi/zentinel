# zentinel documentation

This directory is the contract for zentinel. Specs are normative: the code must
match them, and they change together. Start with the [project README](../README.md)
for an overview, then dive in here.

## User guide

| Doc | What it covers |
|---|---|
| [CLI_SPEC.md](CLI_SPEC.md) | Every command, flag, and exit code |
| [CONFIG_SPEC.md](CONFIG_SPEC.md) | `zentinel.toml` keys, sections, and defaults |
| [MUTATOR_SPEC.md](MUTATOR_SPEC.md) | Mutation operators and the cases they skip |
| [REPORT_FORMAT.md](REPORT_FORMAT.md) | `text` / `json` / `jsonl` / `junit` report formats |
| [DOCTEST_SPEC.md](DOCTEST_SPEC.md) | `zentinel doctest` — verifying doc examples |
| [ERROR_CODES.md](ERROR_CODES.md) | `ZNTL_*` error codes and their meaning |
| [FAILURE_MODES.md](FAILURE_MODES.md) | Known failure modes and how to diagnose them |
| [GLOSSARY.md](GLOSSARY.md) | Terms used throughout the docs |

## Operating zentinel

| Doc | What it covers |
|---|---|
| [PERFORMANCE_STRATEGY.md](PERFORMANCE_STRATEGY.md) | Why runs cost what they do, and the levers that help |
| [SANDBOX_SECURITY.md](SANDBOX_SECURITY.md) | Threat model and sandbox guarantees |
| [TEST_SELECTION.md](TEST_SELECTION.md) | How tests are selected for each mutant |
| [ZIG_VERSION_POLICY.md](ZIG_VERSION_POLICY.md) | Why a single Zig version is pinned per release |
| [CI_STRATEGY.md](CI_STRATEGY.md) | Using zentinel in continuous integration |

## Doctest subsystem

| Doc | What it covers |
|---|---|
| [DOCTEST_SPEC.md](DOCTEST_SPEC.md) | The normative doctest specification |
| [DOCTEST_ARCHITECTURE.md](DOCTEST_ARCHITECTURE.md) | How the doctest pipeline is built |
| [DOCTEST_BLOCK_FORMATS.md](DOCTEST_BLOCK_FORMATS.md) | Recognized code-block formats |
| [DOCTEST_MUTATION_STRATEGY.md](DOCTEST_MUTATION_STRATEGY.md) | Mutating doc examples (`--mutate`) |
| [DOCTEST_AI_INTEGRATION.md](DOCTEST_AI_INTEGRATION.md) | Advisory AI for doctests (opt-in) |
| [DOCTEST_POLICY.md](DOCTEST_POLICY.md) | Policy for what doctest gates and reports |
| [DOCTEST_ROADMAP.md](DOCTEST_ROADMAP.md) | Planned doctest work |

## AI features (opt-in, advisory)

| Doc | What it covers |
|---|---|
| [AI_ASSISTED_UX.md](AI_ASSISTED_UX.md) | UX of `explain` / `suggest` / `review-tests` |
| [AI_CONTEXT_SCHEMA.md](AI_CONTEXT_SCHEMA.md) | The context sent to a provider, and redaction |
| [AI_PROMPT_CONTRACTS.md](AI_PROMPT_CONTRACTS.md) | Prompt and response contracts |

## Contributor reference

| Doc | What it covers |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture and layering |
| [INVARIANTS.md](INVARIANTS.md) | Invariants that must never break |
| [STYLE.md](STYLE.md) | Coding style |
| [INTERNAL_API_CONTRACTS.md](INTERNAL_API_CONTRACTS.md) | Module layers and boundaries |
| [AST_BACKEND.md](AST_BACKEND.md) | The stable AST mutation backend |
| [ZIR_BACKEND.md](ZIR_BACKEND.md) | The experimental ZIR cross-check backend |
| [ZIG_SEMANTICS.md](ZIG_SEMANTICS.md) | Zig semantics zentinel relies on |
| [SCHEMA_REGISTRY.md](SCHEMA_REGISTRY.md) | Versioned JSON schemas under `schemas/` |
| [DEPENDENCY_POLICY.md](DEPENDENCY_POLICY.md) | The zero-dependency policy |
| [DOGFOODING.md](DOGFOODING.md) | Running zentinel on itself |
| [adr/](adr/) | Architecture Decision Records |

## Direction

| Doc | What it covers |
|---|---|
| [VISION.md](VISION.md) | What zentinel is for |
| [NON_GOALS.md](NON_GOALS.md) | What zentinel deliberately will not do |
| [ROADMAP.md](ROADMAP.md) | Planned work |
