# 022 Dogfood Fixture Run

Sequential guard: start this task only after task 021 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Add the first zentinel dogfood workflow over fixture projects.

## Scope

- Create a dogfood config that targets mutation fixtures.
- Add a build or script entry that runs zentinel against fixtures.
- Verify report determinism across repeated fixture dogfood runs.
- Keep production zentinel source out of dogfood scope for now.

## Files allowed to modify

- `zentinel.dogfood.toml`
- `build.zig`
- `scripts/**`
- `test/dogfood_fixture_test.zig`
- `test/fixtures/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`

## Required tests

- Add a failing test or script check for dogfood config parsing.
- Add a failing determinism check that two fixture dogfood runs produce equivalent normalized reports.
- Run `zig build test`.
- Run the fixture dogfood command and record the result.

## Acceptance criteria

- Fixture dogfood can be run by a documented command.
- Dogfood report is archived under a deterministic output path.
- The workflow does not require network access or AI.
- Production zentinel modules are not mutated yet.

## Non-goals

- CI gating.
- Full self-mutation.
- Performance optimization.
- AI survivor review.

## Suggested implementation approach

1. Start with the smallest fixture set covering Phase 1 operators.
2. Normalize report durations before determinism comparison.
3. Keep command invocation explicit and documented in status.
4. Avoid adding thresholds at this stage.

## Dogfooding implications

This task activates Stage 1 dogfooding and becomes the proof path for new mutators.

## Follow-up tasks

- `tasks/023-optional-null-mutators.md`
