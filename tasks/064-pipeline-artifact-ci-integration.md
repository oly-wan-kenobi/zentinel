# 064 Pipeline Artifact CI Integration

Sequential guard: start this task only after task 062 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Integrate pipeline artifact validation into the repository CI entrypoint.

## Scope

- Add pipeline artifact checks to `scripts/ci.sh` once the validator supports them.
- Document required CI artifact outputs.
- Ensure CI reports missing or invalid pipeline artifacts with deterministic diagnostics.
- Preserve network-free default CI behavior.

## Files allowed to modify

- `scripts/**`
- `docs/CI_STRATEGY.md`
- `docs/VERIFICATION_PIPELINE.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `test/fixtures/pipeline/ci_artifacts/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/**`
- `test/**/*.zig`
- `build.zig`
- `docs/MUTATOR_SPEC.md`
- `docs/DOCTEST_*.md`

## Required tests

- Add a failing CI fixture or script test for invalid pipeline artifact metadata.
- Add a failing check that `scripts/ci.sh` runs task-system and pipeline artifact validation.
- Run `python3 scripts/validate_task_system.py`.
- Run `scripts/ci.sh` if it exists and prerequisites are available.

## Acceptance criteria

- CI invokes pipeline metadata validation.
- CI artifact diagnostics use project-relative paths.
- Default CI remains deterministic and network-free.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Adding hosted CI provider configuration.
- Uploading artifacts to remote storage.
- Changing mutation result semantics.

## Suggested implementation approach

1. Start with a fixture that fails the new CI artifact check.
2. Wire the check through the canonical in-repository CI script.
3. Document required artifacts without adding provider-specific YAML.
4. Keep output stable for snapshots.

## Dogfooding implications

CI artifact validation makes release and dogfood evidence auditable across fresh agent sessions.

## Follow-up tasks

- `tasks/065-failure-recovery-validator.md`
