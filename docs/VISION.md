# zentinel Vision

zentinel is a Zig-native mutation testing framework for developers who need compiler-grade feedback about whether their tests actually protect meaningful behavior.

The framework exists because Zig projects exercise behaviors that generic mutation tools do not understand well:

- compile-time execution and `comptime` control flow
- same-file `test` declarations
- explicit allocators and allocation failure handling
- error unions, optionals, `defer`, and `errdefer`
- safety mode differences across Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall
- build graph behavior driven by `build.zig`

zentinel treats these as first-class language features, not edge cases.

## Product Promise

zentinel should answer one practical question:

> Which surviving changes reveal tests that are missing, weak, or misleading?

It must do that with deterministic execution, precise source mapping, actionable reports, and AI assistance that explains evidence without changing the evidence.

## Core Principles

| Principle | Requirement |
| --- | --- |
| Zig-native first | Use Zig's syntax, build model, testing conventions, and compiler behavior as the design center. |
| Latest stable Zig only | Support only the current latest stable Zig release. Older Zig versions are not compatibility targets. |
| Deterministic core | Mutation generation, execution, result classification, IDs, reports, and cache keys must be reproducible. |
| TDD-first development | Every behavior begins with a failing test or fixture before implementation. |
| Phased delivery | Stable AST-based capability ships before experimental compiler IR backends. |
| Dogfood early | zentinel must mutate its own code as soon as the core can do so safely. |
| AI-assisted, not AI-decided | AI may explain, group, and suggest. It must never determine kill/survival/correctness. |

## User Experience North Star

zentinel UX should feel:

- diagnostic
- compiler-native
- actionable
- fast
- trustworthy

zentinel UX should not feel:

- academic
- noisy
- percentage-obsessed
- dependent on remote services
- vague about what happened

Mutation score is a secondary signal. The primary signal is the concrete surviving mutant with source context, test command, result evidence, and suggested next action.

## Example Experience

Given a source branch:

```zig
if (idx >= items.len) return error.OutOfBounds;
```

zentinel may generate:

```diff
- if (idx >= items.len) return error.OutOfBounds;
+ if (idx > items.len) return error.OutOfBounds;
```

The deterministic report records whether tests killed or survived the mutant. If it survived, an AI explanation may say:

```text
The boundary value idx == items.len appears untested. Add a test that passes an index exactly equal to len and expects error.OutOfBounds.
```

The AI text is advisory. The survivor status is determined only by compiling and running the selected tests.

## Audience

Primary users:

- Zig library authors
- systems programmers maintaining correctness-critical code
- teams that already run `zig test` in CI
- developers building allocator-aware, error-aware, and comptime-heavy code

Secondary users:

- CI maintainers who need deterministic reports
- editor integration authors
- AI coding agents that need strict contracts for safe sequential work

## Non-Goals

The complete scope boundary lives in `docs/NON_GOALS.md`. In short,
zentinel is not:

- a general-purpose test runner replacement
- a fuzzing engine
- a code coverage product
- a source formatter
- a multi-language mutation framework
- an AI system that decides whether tests are correct
- a compatibility layer for old Zig releases

## Long-Term Direction

The stable product starts with an AST/source backend because users need reliable behavior early. Experimental ZIR and AIR backends will later explore deeper semantic mutation while preserving the same shared mutant model and deterministic report contract.

The long-term goal is:

> zentinel becomes the mutation testing platform that understands compile-time systems programming.
