# 089 Zig Version Verification Blocker Policy

Sequential guard: start this task only after task `088` is complete and `tasks/status.json` names `089` as the next queued task. No later-order task may begin until this task is complete.

## Goal

Make task `005` self-contained for autonomous agents by requiring official latest-stable Zig verification and a concrete blocker path when that verification cannot be performed.

## Scope

- Clarify `docs/ZIG_VERSION_POLICY.md` so unavailable network or official release source access blocks task `005` instead of allowing a guess.
- Clarify task `005` required tests and acceptance criteria with the same blocker rule.
- Add validator guardrails for the official-source unavailable path.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/089-zig-version-verification-blocker-policy.md`
- `tasks/000-project-bootstrap.md`
- `tasks/005-version-policy.md`
- `docs/ZIG_VERSION_POLICY.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `docs/MUTATOR_SPEC.md`
- `.claude/**`

## Required tests

- Add a failing validator guardrail requiring `docs/ZIG_VERSION_POLICY.md` to define the unavailable official-source blocker path.
- Add a failing validator guardrail requiring task `005` to block and insert a prerequisite task instead of guessing when official latest-stable Zig verification cannot be performed.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating docs and task wording.
- Run `python3 scripts/validate_task_system.py` after the contracts are aligned.

## Acceptance criteria

- Task `005` requires official release source verification before choosing the compiled-in supported Zig version.
- Task `005` explicitly blocks with a concrete prerequisite task if network access or the official release source is unavailable.
- `docs/ZIG_VERSION_POLICY.md` remains version-agnostic and forbids local-toolchain-only inference.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Looking up the current Zig release now.
- Implementing the version checker.
- Adding an offline mirror policy beyond the blocker path.

## Suggested implementation approach

1. Add validator phrase checks first and confirm they fail on current task/version-policy wording.
2. Update only task `005` and `docs/ZIG_VERSION_POLICY.md`.
3. Complete this pre-bootstrap clarity task and leave project bootstrap as the next dependency-ready task.

## Dogfooding implications

No runtime behavior exists yet. This task prevents future dogfood and CI work from using an unsupported or guessed Zig version.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
