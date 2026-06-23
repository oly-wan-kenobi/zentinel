# zentinel

Mutation testing for [Zig](https://ziglang.org). Written in Zig, for Zig projects.

zentinel makes small, targeted changes to your source code (*mutants*) — flipping a
`<` to `<=`, swapping `and` for `or`, negating a boolean — and runs your test suite
against each one. If your tests still pass with the bug injected, the mutant
**survived**, and zentinel shows you exactly which behavior your tests never check.

Line coverage tells you your tests *ran* the code. Mutation testing tells you
whether they would *notice if it broke*.

## Status

- Requires **Zig 0.16.0** (pinned; pre-1.0 Zig changes quickly, and zentinel tracks it release by release).
- The **AST backend is the stable default**. A ZIR-based backend exists for cross-checking mutation sites against the compiler's intermediate representation; ZIR is an unstable internal compiler format, so this backend is validated per Zig release and should be considered advanced/experimental.
- AI-assisted features are **opt-in and disabled by default**. The core pipeline is deterministic and runs fully offline.

## Install

```sh
git clone https://github.com/oly-wan-kenobi/zentinel
cd zentinel
zig build -Doptimize=ReleaseSafe
# binary at zig-out/bin/zentinel — put it on your PATH
```

## Quickstart

In your Zig project:

```sh
zentinel init    # writes a commented zentinel.toml with safe defaults
zentinel check   # validates config and environment
zentinel run
```

Example output against a small project with a `clamp` function whose tests miss
the exact boundaries:

```text
survived 2 comparison_boundary src/main.zig:8
  -     if (x < lo) return lo;
  +     if (x <= lo) return lo;
  selected tests: zig test src/main.zig
  likely focus: missing exact-boundary inputs
survived 3 comparison_boundary src/main.zig:9
  -     if (x > hi) return hi;
  +     if (x >= hi) return hi;
  selected tests: zig test src/main.zig
  likely focus: missing exact-boundary inputs
3 mutants: 1 killed, 2 survived
```

Each survivor is a concrete, reproducible gap in your test suite: the diff that
was applied, the test command that failed to catch it, and a hint about what
kind of input is missing.

## Commands

| Command | What it does |
|---|---|
| `zentinel init` | create a commented `zentinel.toml` |
| `zentinel check` | validate config and environment |
| `zentinel list-mutants` | list generated mutants without running tests |
| `zentinel run` | run mutation testing |
| `zentinel doctest` | verify the code examples in your docs actually compile and pass |
| `zentinel version` | print zentinel and Zig versions |
| `zentinel explain` / `suggest` / `review-tests` | advisory AI review of mutants/survivors (opt-in) |

Run `zentinel <command> --help` for per-command flags.

## Mutation operators

Enabled by default: `arithmetic_add_sub`, `arithmetic_mul_div`, `equality_swap`,
`comparison_boundary`, `logical_and_or`, `boolean_literal`. Operators are
selected per project in `zentinel.toml`. See
[docs/MUTATOR_SPEC.md](docs/MUTATOR_SPEC.md) for exact semantics, including the
cases each operator deliberately skips to avoid generating uncompilable or
trivially-equivalent mutants.

## CI usage

```sh
zentinel run --fail-on-survivors --report junit
```

- Exit code `0` when all mutants are killed, `1` with `--fail-on-survivors` when any survive.
- `--report <text|json|jsonl|junit>` writes machine-readable reports (default output dir: `zig-out/zentinel`). Schemas are documented in [docs/REPORT_FORMAT.md](docs/REPORT_FORMAT.md).
- A baseline (unmutated) test run is required before mutants execute, so a broken suite fails fast instead of producing nonsense scores.

## Configuration

`zentinel init` generates a fully commented config. The shape:

```toml
[project]
name = "my-project"
include = ["src/**/*.zig"]
exclude = [".zig-cache/**", "zig-out/**", "test/**"]

[mutators]
enabled = ["comparison_boundary", "logical_and_or", "boolean_literal", ...]

[test]
commands = ["zig build test"]
timeout_ms = 30000

[run]
jobs = 1            # parallel workers; each runs in an isolated workspace

[ai]
enabled = false     # advisory AI is opt-in; nothing leaves your machine by default
```

Full reference: [docs/CONFIG_SPEC.md](docs/CONFIG_SPEC.md).

## Doctest verification

`zentinel doctest` extracts the code examples from your documentation, compiles
and runs them, and reports drift — so your README examples can't silently rot.
It can also run the mutation pipeline against doc examples
(`zentinel doctest --mutate`) to check that your examples actually assert
behavior rather than just executing. See [docs/DOCTEST_SPEC.md](docs/DOCTEST_SPEC.md).

## Performance: what to expect

Honest numbers up front: **every mutant currently compiles your project from a
cold Zig cache.** Mutant workspaces are fully isolated — each gets its own
working tree and its own `ZIG_LOCAL_CACHE_DIR` — which makes results
deterministic and prevents any cross-mutant cache poisoning, but it means a run
costs roughly `(your clean build time + test time) × number of mutants`. On a
small project that's seconds per mutant; on a large one it adds up.

This is a deliberate correctness-over-speed default, not an oversight: sharing
a warm compiler cache across mutants would break the per-worker isolation
invariant the result semantics are built on, and under today's non-incremental
Zig compilation a warm cache saves less than you'd hope (a mutated source file
forces full semantic analysis anyway). That last point is now measured rather
than asserted — see [docs/PERFORMANCE_STRATEGY.md](docs/PERFORMANCE_STRATEGY.md):
profiling zentinel against its own tree found a warm *local* cache saves only
**0–9%** on a real mutant, because the dominant cost is test execution (which no
cache touches) and a mutated file re-invalidates most of the build graph. So the
highest-payoff lever is cutting the mutant *count*, not warming the cache.

Mitigations that exist now:

- `run.jobs = N` runs mutants in parallel.
- **Diff-scoped runs** mutate only the files you changed (opt-in, default off):
  - `zentinel run --changed-only` — files changed in your working tree (vs `HEAD`).
  - `zentinel run --diff <ref>` — files changed vs a base ref (e.g. `main`), for CI.
  - `zentinel run --scope-files a.zig,b.zig` — an explicit list (git-free).
  These narrow which files are mutated; every retained mutant's verdict is
  byte-for-byte identical to the full run (scoping omits, never changes, results).
- Scoped `include` globs and operator selection keep the mutant count down.
- The result cache computes a content key per mutant today, but **result reuse
  across runs is not wired yet** — it does not yet skip unchanged mutants.

On the roadmap, in order of payoff now that the warm-cache lever is measured
marginal: wiring result-cache reuse (skip unchanged mutants on re-runs) and
coverage-guided test selection (run only the tests that exercise a mutant).

## Security model

Mutants are arbitrary code compiled and executed on your machine — the same
trust model as running your own test suite, but zentinel still constrains the
blast radius: mutant workspaces are sandboxed per worker, environment is
reduced to a minimal allowlist, and all report/cache writes are confined to the
project root (symlink escapes are rejected). Details in
[docs/SANDBOX_SECURITY.md](docs/SANDBOX_SECURITY.md).

## AI features (opt-in)

`explain`, `suggest`, and `review-tests` can ask an LLM to explain a surviving
mutant or draft the missing test. These are advisory only — they never gate a
run, are disabled by default (`ai.enabled = false`, `remote_allowed = false`),
and the context sent to a provider passes through a redaction layer
(secret-pattern and path redaction with an audit trail). The deterministic
pipeline never requires a network.

## Documentation

User docs:
[CLI](docs/CLI_SPEC.md) ·
[Configuration](docs/CONFIG_SPEC.md) ·
[Mutation operators](docs/MUTATOR_SPEC.md) ·
[Report formats](docs/REPORT_FORMAT.md) ·
[Doctest](docs/DOCTEST_SPEC.md) ·
[Error codes](docs/ERROR_CODES.md)

Contributor docs:
[Architecture](docs/ARCHITECTURE.md) ·
[Style](docs/STYLE.md) ·
[Invariants](docs/INVARIANTS.md) ·
[ADRs](docs/adr/)

zentinel runs on itself: `scripts/dogfood.sh`.

## License

[MIT](LICENSE)
