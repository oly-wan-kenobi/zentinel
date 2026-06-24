# Changelog

All notable changes to zentinel are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While zentinel is pre-1.0, the public surface (CLI, config, report schemas) may
change between minor versions; breaking changes are called out here.

## [Unreleased]

## [0.1.0] - 2026-06-24

Initial public release. zentinel performs mutation testing for Zig projects:
it applies small, targeted source mutations, runs your test suite against each,
and reports which mutants survived — the gaps your tests don't catch.

### Added

- **Mutation pipeline** with a stable AST backend and an experimental ZIR
  cross-check backend.
- **Mutation operators**: `arithmetic_add_sub`, `arithmetic_mul_div`,
  `equality_swap`, `comparison_boundary`, `logical_and_or`, `boolean_literal`,
  selected per project in `zentinel.toml`. See `docs/MUTATOR_SPEC.md`.
- **CLI commands**: `init`, `check`, `list-mutants`, `run`, `doctest`,
  `version`, and the opt-in advisory AI commands `explain`, `suggest`, and
  `review-tests`. See `docs/CLI_SPEC.md`.
- **Diff-scoped runs**: `--changed-only`, `--diff <ref>`, and
  `--scope-files` narrow which files are mutated without changing any verdict.
- **Reports** in `text`, `json`, `jsonl`, and `junit` formats, with versioned
  JSON schemas under `schemas/`. See `docs/REPORT_FORMAT.md`.
- **Doctest verification** (`zentinel doctest`): compiles and runs the code
  examples in your docs, with an optional `--mutate` mode. See
  `docs/DOCTEST_SPEC.md`.
- **Sandboxing**: per-worker isolated mutant workspaces, a minimal environment
  allowlist, and report/cache writes confined to the project root with
  symlink-escape rejection. See `docs/SANDBOX_SECURITY.md`.
- **Opt-in AI features**, disabled by default, with a redaction layer on
  outbound context and an audit trail. The deterministic core never requires a
  network.
- MIT license and a CI workflow gating formatting, build, tests, and a
  self-dogfood run.

### Notes

- Requires **Zig 0.16.0** exactly; see `docs/ZIG_VERSION_POLICY.md`.
- Result-cache reuse across runs (skipping unchanged mutants) is not yet wired;
  see `docs/PERFORMANCE_STRATEGY.md` and `docs/ROADMAP.md`.

[Unreleased]: https://github.com/oly-wan-kenobi/zentinel/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/oly-wan-kenobi/zentinel/releases/tag/v0.1.0
