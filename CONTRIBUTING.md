# Contributing to zentinel

Thanks for your interest in zentinel — mutation testing for Zig, written in Zig.
This guide covers how to build, test, and propose changes. For a deeper
orientation to the codebase, read [`AGENTS.md`](AGENTS.md) and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Prerequisites

- **Zig 0.16.0**, exactly. zentinel pins a single Zig version per release
  because pre-1.0 Zig changes quickly; see
  [`docs/ZIG_VERSION_POLICY.md`](docs/ZIG_VERSION_POLICY.md).
- A POSIX shell to run the helper scripts under `scripts/`.

## Build and test

```sh
zig build                          # build the binary (zig-out/bin/zentinel)
zig build test                     # run the full test suite (must stay green)
zig fmt --check src test build.zig # formatting gate (CI enforces this)
scripts/ci.sh                      # full local CI: fmt, build, tests, dogfood
```

`scripts/ci.sh` mirrors what CI runs, so a green `scripts/ci.sh` is the bar a
pull request must clear. zentinel also runs on itself —
`scripts/dogfood.sh` — which is a good way to see the tool in action.

## How we work

zentinel treats `docs/` as the contract, not as after-the-fact description:

- **Specs are normative.** `CLI_SPEC`, `CONFIG_SPEC`, `MUTATOR_SPEC`,
  `REPORT_FORMAT`, `DOCTEST_SPEC`, and `ERROR_CODES` describe behavior the code
  must match. Change the spec and the code together — never let them drift. Some
  docs contain executable doctest blocks that CI verifies.
- **Every bug fix needs a regression test** that fails before the fix and passes
  after it.
- **Determinism is a hard invariant.** Output must use stable ordering, stable
  IDs, and normalized paths. Mutation verdicts (killed / survived / equivalent)
  are decided only by deterministic test evidence — AI features are advisory and
  must never decide a verdict. See [`docs/INVARIANTS.md`](docs/INVARIANTS.md).
- **Architecture decisions live in [`docs/adr/`](docs/adr/).** If a change
  conflicts with an accepted ADR, either follow the ADR or write a superseding
  one — don't silently diverge.

Coding style is documented in [`docs/STYLE.md`](docs/STYLE.md). Run `zig fmt`
before committing and keep `zig build test` at zero failures.

## Submitting changes

1. Fork the repository and create a topic branch.
2. Make your change, with tests and any matching spec updates.
3. Ensure `scripts/ci.sh` passes locally.
4. Open a pull request. Fill in the PR template, describe the motivation, and
   link any related issue.

Small, focused pull requests are easier to review and land faster. If you are
planning a large or architecturally significant change, please open an issue
first to discuss the approach.

## Reporting bugs and requesting features

Use the GitHub issue templates. A good bug report includes the zentinel and Zig
versions (`zentinel version`), the exact command you ran, and what you expected
versus what happened. See [`docs/FAILURE_MODES.md`](docs/FAILURE_MODES.md) for
known failure modes and their error codes before filing.

## Security

Please do not file public issues for security vulnerabilities. See
[`SECURITY.md`](SECURITY.md) for how to report them privately.

## Code of conduct

By participating in this project you agree to abide by the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

zentinel is [MIT licensed](LICENSE). By contributing, you agree that your
contributions will be licensed under the same terms.
