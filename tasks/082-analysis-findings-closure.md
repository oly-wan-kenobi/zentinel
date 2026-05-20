# 082 Analysis Findings Closure

Sequential guard: start this task only after task 081 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Resolve the pre-bootstrap analysis findings that could cause autonomous agents to implement zentinel from ambiguous or weakly checked contracts.

## Scope

- Clarify supported doctest Markdown fence lengths.
- Add validator guardrails for doctest fence contract drift, task gate-section headings, task 000 task-control scope, and latest-stable Zig official-source policy.
- Standardize property-test gate headings in doctest task files.
- Make task 000's task-control lifecycle files explicit in its allowed scope.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/082-analysis-findings-closure.md`
- `tasks/000-project-bootstrap.md`
- `tasks/005-version-policy.md`
- `tasks/030-doctest-conventions.md`
- `tasks/031-doctest-parser.md`
- `tasks/032-doctest-extraction.md`
- `tasks/033-doctest-runner.md`
- `tasks/034-doctest-snapshots.md`
- `tasks/035-cli-doctests.md`
- `tasks/036-config-doctests.md`
- `tasks/037-mutator-spec-doctests.md`
- `tasks/038-doctest-cache.md`
- `tasks/039-doctest-mutation-experiments.md`
- `docs/DOCTEST_ARCHITECTURE.md`
- `docs/DOCTEST_BLOCK_FORMATS.md`
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

- Add failing validator guardrails for the doctest fence-length contract before aligning the docs and task 031.
- Add failing validator guardrails rejecting legacy `## Property tests required` headings and requiring gate sections with canonical headings when present.
- Add a failing validator guardrail requiring task 000 to allow every task-control lifecycle file explicitly.
- Add validator coverage proving `docs/ZIG_VERSION_POLICY.md` and task 005 preserve official latest-stable Zig source verification.
- Run `python3 scripts/validate_task_system.py`.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax checks for edited task-control files.
- Run `git diff --check`.

## Acceptance criteria

- Doctest fence support is unambiguous between architecture, block-format docs, task 031, and the validator.
- Property-test task gate headings are canonical and validator-backed.
- Task 000 visibly permits all task-control lifecycle files while preserving the Task Queue Manager exception.
- Latest-stable Zig policy remains version-agnostic and validator-backed against local-version-only inference.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing Zig source, build files, or tests.
- Implementing doctest parsing.
- Changing mutator semantics.
- Adding dependencies.

## Suggested implementation approach

1. Add structural validator checks first and record the expected failures.
2. Align the smallest set of docs and task files needed for those checks to pass.
3. Keep edits ASCII-only and avoid broad reformatting.
4. Re-run validator, Python compilation, JSON syntax checks, and whitespace checks.

## Dogfooding implications

No dogfood run exists yet. This task removes pre-bootstrap ambiguity before agents create the first Zig scaffold.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
