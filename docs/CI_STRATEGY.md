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
| Experimental backend jobs | Validate ZIR/AIR without blocking stable path. | 5+ |

## Required Baseline Jobs

The canonical in-repository CI entrypoint is:

```bash
scripts/ci.sh
```

Hosted provider workflow files such as `.github/workflows/*.yml` are out of scope until a task explicitly allows them. CI tasks wire and document `scripts/ci.sh`; external systems may call that script.

Every CI run must include:

```bash
python3 scripts/validate_task_system.py
zig version
zig build test
```

When implementation provides lint or format checks, `scripts/ci.sh` should run them without modifying files.

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

Final release dogfood archives live under `artifacts/pipeline/<task-id>/dogfood/`; `zig-out` paths are runtime output paths, not canonical archives.

Advisory dogfood should fail only on infrastructure or deterministic core errors, not ordinary survivors.

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

ZIR and AIR jobs must be:

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
