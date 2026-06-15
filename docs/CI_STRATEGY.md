# CI Strategy

zentinel CI must protect deterministic behavior first. Mutation testing is added in phases so CI remains fast and trustworthy.

## CI Layers

| Layer | Purpose | Required Phase |
| --- | --- | --- |
| Format/check | Keep repository mechanically consistent. | 0 |
| Unit tests | Validate pure behavior. | 0 |
| Fixture tests | Validate mutation semantics. | 1 |
| Contract tests | Protect report/config/AI schemas. | 1-4 |
| Dogfood advisory | Run zentinel on selected zentinel modules. | 2-3 |
| Dogfood gating | Fail on protected mutation regressions. | 4+ |
| Experimental backend jobs | Validate ZIR without blocking stable path. | 5+ |

## Required Baseline Jobs

The canonical in-repository CI entrypoint is:

```bash
scripts/ci.sh
```

The hosted GitHub Actions workflow `.github/workflows/ci.yml` installs the pinned Zig version and calls `scripts/ci.sh`; it adds no CI logic of its own. External systems may likewise call that script.

Every CI run must include:

```bash
zig version
zig build test
```

When implementation provides lint or format checks, `scripts/ci.sh` should run them without modifying files.

`scripts/ci.sh` runs the required deterministic stages in a fixed order and must not require remote AI providers.

## Mutation Fixture Job

Once Phase 1 exists:

```bash
zig build test-fixtures
zentinel run --config test/fixtures/zentinel.toml --report json
```

The exact command may differ after build integration, but the job must verify:

- all stable operators have fixture coverage
- reports match schema
- output is deterministic across repeated runs

## Dogfood CI

Dogfood CI starts advisory:

```bash
zentinel run --config zentinel.dogfood.toml --report json --output zig-out/zentinel/dogfood.json
```

Artifacts:

- JSON report
- text summary
- cache diagnostics when enabled

Advisory dogfood should fail only on infrastructure or deterministic core errors, not ordinary survivors.

## Canonical Entrypoint

`scripts/ci.sh` is the canonical in-repository CI entrypoint. It runs the required deterministic stages in order and is network-independent (no remote AI providers):

1. `format_check` — `zig fmt --check src test build.zig`
2. `build` — `zig build`
3. `unit_tests` — `zig build test` (this includes the real-binary integration test `test/integration_run_test.zig`, which builds `zentinel` and runs it over the committed fixture project `test/fixtures/integration/sample`, asserting the report's killed/survived counts so the real `src/cli.zig` I/O adapters — process execution, per-mutant workspace tree-copy, and JSON report writing — are exercised, not only the mock-executor unit tests)
4. `advisory_dogfood` — `scripts/dogfood.sh` (advisory; survivors are reviewed, not a failure)

`scripts/ci.sh --list` prints the stage names in order without running them.

Selected production-source dogfood is opt-in via `scripts/dogfood-production.sh` (config `test/fixtures/dogfood/production/config.toml`); its deterministic reference reports live at `test/fixtures/dogfood/production/run1.report.json` and `run2.report.json`, which normalize to the same bytes across repeated runs.

## Gating Policy

CI may fail on:

- baseline failure
- invalid mutants
- report schema violation
- unsupported Zig version
- nondeterministic output
- protected-module survivor regression after gating is explicitly enabled

CI should not fail on:

- AI provider unavailability in deterministic jobs
- experimental backend failure in stable jobs
- mutation score below an arbitrary global percentage

## Experimental Backends

ZIR jobs must be:

- clearly named experimental
- opt-in or non-blocking until promoted
- isolated from stable AST mutation jobs
- allowed to fail only if the project explicitly chooses that policy

## Network Policy

Default CI must not require network access after dependencies and Zig are installed. AI tests use the stub provider only.

Remote AI provider tests, if ever added, must run in separate opt-in jobs with explicit secrets and no deterministic report authority.

## Artifact Policy

CI should upload:

- JSON reports
- text summaries
- benchmark summaries
- dogfood reports

Artifacts must not include:

- secrets
- full temporary workspaces
- remote AI prompts unless privacy review explicitly allows them
