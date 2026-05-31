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

`scripts/ci.sh` runs the verification stages defined in `docs/VERIFICATION_PIPELINE.md` that are available for the current phase, in the same required order, and must not require remote AI providers.

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

## Canonical Entrypoint

`scripts/ci.sh` is the canonical in-repository CI entrypoint (task `059`). It runs the required deterministic stages in order and is network-independent (no remote AI providers):

1. `format_check` — `zig fmt --check src test build.zig`
2. `build` — `zig build`
3. `unit_tests` — `zig build test`
4. `task_system_validation` — `python3 scripts/validate_task_system.py`
5. `pipeline_artifact_validation` — `python3 scripts/check_pipeline_artifacts.py`
6. `advisory_dogfood` — `scripts/dogfood.sh` (advisory; survivors are reviewed, not a failure)
7. `release_dogfood_gate` — `python3 scripts/release_dogfood_gate.py` (final release dogfood gate, task `085`)

`scripts/ci.sh --list` prints the stage names in order without running them.

### Final Release Dogfood Gate

Stage `release_dogfood_gate` (task `085`) is the final release gate that runs before task `060` release acceptance, after the late hardening and advisory tasks (`061`, `062`, `064`, `065`, `066`, `067`) have landed. `scripts/release_dogfood_gate.py` validates the release-evidence manifest `test/fixtures/release/valid/release_evidence.json` and self-tests against `test/fixtures/release/{valid,invalid}`. The gate passes only when:

- every required sub-gate passed with archived or test-verified evidence: `fixture_dogfood`, `internal_module_dogfood`, `public_docs_doctest`, `mutation_aware_doctest`, `doctest_survivor_ai`, `pipeline_artifact_validation`, and `failure_recovery_validation`;
- the archived deterministic dogfood reports under `artifacts/pipeline/085/dogfood/` exist and the repeated `run1`/`run2` pair normalizes to identical bytes;
- the protected scope has no invalid mutants; and
- every protected-scope survivor is resolved (fixed by a test or recorded with deterministic equivalent-risk review evidence under `artifacts/pipeline/085/dogfood/`).

The check is deterministic and network-free; diagnostics use project-relative paths. `zig-out` runtime outputs are not the canonical archive.

### Pipeline Artifact Validation

Stage `pipeline_artifact_validation` (task `064`) makes committed pipeline evidence auditable in CI across fresh agent sessions. `scripts/check_pipeline_artifacts.py` reuses the project-owned subset validator in `scripts/validate_task_system.py` to:

- validate the committed `artifacts/pipeline/<task-id>/` tree (handoffs, `locks/active-task-lock.json`, and `context/` packets) against the baseline pipeline schemas, and
- self-test that check against `test/fixtures/pipeline/ci_artifacts/`, where `valid/` must pass and every `invalid/<case>/` must be rejected.

The check is deterministic and network-free. Diagnostics use project-relative paths (for example `artifacts/pipeline/064/locks/active-task-lock.json: active lock task_id ...`) and are emitted in sorted order so CI output is stable for snapshots. A schema or task-scope violation in any committed pipeline artifact exits non-zero and blocks CI. Modes: `--real-tree` validates only the committed tree; `--self-test` validates only the fixtures; the default runs both.

Required CI artifact outputs: every post-`041` task contributes a `verification/report.json` (`zentinel.pipeline.verification.v1`) under `artifacts/pipeline/<task-id>/`, plus any role handoffs, active lock, and context packets it produces; this stage is the gate that keeps those metadata artifacts schema-valid and task-scoped. Selected initial production-source dogfood is opt-in via `scripts/dogfood-production.sh` (config `test/fixtures/dogfood/production/config.toml`); its deterministic reference reports live at `test/fixtures/dogfood/production/run1.report.json` and `run2.report.json`, which normalize to the same bytes across repeated runs. Task `059` is the initial advisory dogfood CI and is not the final release dogfood gate; task `085` is the final release dogfood gate.

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
