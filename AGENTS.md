# AGENTS.md

zentinel is a mutation testing tool for Zig, written in Zig. It mutates Zig
source (e.g. `<` → `<=`, `and` → `or`), runs the project's tests against each
mutant, and reports which mutants survived. The core pipeline is deterministic
and offline; AI features are advisory-only and disabled by default.

## Build and Test

```bash
zig build                          # build the binary (zig-out/bin/zentinel)
zig build test                     # run the full test suite (must stay green)
zig fmt --check src test build.zig # formatting gate (CI enforces this)
scripts/ci.sh                      # full local CI: fmt, build, tests, dogfood
```

Requires Zig 0.16.0 exactly (see docs/ZIG_VERSION_POLICY.md).

## Orientation

- `src/` — implementation. Each file declares a `// Layer:` (see
  docs/INTERNAL_API_CONTRACTS.md); deterministic core must not import adapters.
- `test/` — tests, auto-discovered as `test/**/*_test.zig`. Fixtures live under
  `test/fixtures/`.
- `docs/` — the contract. Start with docs/ARCHITECTURE.md, docs/STYLE.md, and
  docs/INVARIANTS.md. Specs (CLI_SPEC, CONFIG_SPEC, MUTATOR_SPEC,
  REPORT_FORMAT, DOCTEST_SPEC, ERROR_CODES) are normative.
- `schemas/` — versioned JSON schemas for machine-readable artifacts.

## Rules

- Specs in `docs/` are the contract: change spec and code together, never let
  them drift. Some docs contain executable doctest blocks verified in CI.
- Every bug fix needs a regression test that fails before the fix.
- Mutation results are determined only by deterministic test evidence — AI must
  never decide killed/survived/equivalent.
- Keep output deterministic: stable ordering, stable IDs, normalized paths.
- Run `zig fmt` before committing; keep `zig build test` at zero failures.
