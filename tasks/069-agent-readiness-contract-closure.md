# 069 Agent Readiness Contract Closure

Sequential guard: start this task only after task 068 is complete in `tasks/STATUS.md`. This task has execution order `000.0` and must complete before task `000`.

## Goal

Resolve the remaining pre-bootstrap contract inconsistencies that would otherwise block autonomous agents from implementing documented zentinel behavior.

## Scope

- Define explicit task ownership for documented `zentinel run` options.
- Align config validation and concurrency settings with `docs/CONFIG_SPEC.md`.
- Align mutation agent role wording with the `compiler_crash` result contract.
- Define baseline timeout report semantics before runner implementation.
- Move pipeline metadata validation immediately after durable handoff artifacts are introduced.
- Align doctest snapshot architecture wording with the doctest spec.
- Add validator guardrails for the corrected contracts.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/002-config-parser.md`
- `tasks/006-report-schema.md`
- `tasks/014-baseline-runner.md`
- `tasks/016-minimal-run-command.md`
- `tasks/018-report-renderers.md`
- `tasks/021-cache-key-design.md`
- `tasks/034-doctest-snapshots.md`
- `tasks/041-handoff-artifacts.md`
- `tasks/042-context-packet-system.md`
- `tasks/050-parallel-worker-pool.md`
- `tasks/058-safety-mode-matrix.md`
- `tasks/063-pipeline-metadata-validator.md`
- `tasks/069-agent-readiness-contract-closure.md`
- `docs/CLI_SPEC.md`
- `docs/CONFIG_SPEC.md`
- `docs/REPORT_FORMAT.md`
- `docs/DOCTEST_ARCHITECTURE.md`
- `.agents/roles/mutation-agent.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `docs/MUTATOR_SPEC.md`

## Required tests

- Add failing validator guardrails before correcting the contracts when validator behavior changes.
- Run `python3 scripts/validate_task_system.py` before and after contract edits.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run JSON syntax validation for edited JSON files.
- Run JSON fence validation for edited Markdown files.
- Run `git diff --check`.

## Acceptance criteria

- Every documented `zentinel run` option has a task owner whose allowed files permit implementation and tests.
- Config parser task coverage includes mutator special-value expansion and all documented validation rejections, including worker count.
- `compiler_crash` is present in the mutation agent role profile and protected by the validator.
- Baseline timeout maps to a deterministic baseline failure report shape.
- Pipeline metadata validation executes immediately after task `041` before later pipeline tasks rely on JSON artifacts.
- Doctest snapshot match-mode architecture wording includes every match mode required by `docs/DOCTEST_SPEC.md`.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing zentinel runtime behavior.
- Adding Zig source files or Zig tests.
- Changing stable task IDs.
- Weakening report, config, doctest, or AI authority contracts.

## Suggested implementation approach

1. Activate this task before project bootstrap and record the pre-fix validator state.
2. Add validator guardrails that expose the stale or missing contracts.
3. Patch the affected specs, task files, role profile, and task ordering narrowly.
4. Re-run validator, JSON, Markdown fence, Python compile, and whitespace checks.
5. Mark this task complete and leave task `000` as the next task.

## Dogfooding implications

This task removes agent-blocking ambiguity before dogfoodable behavior exists. No dogfood run is expected.

## Follow-up tasks

- None predefined.
