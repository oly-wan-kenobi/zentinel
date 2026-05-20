# 068 Preimplementation Contract Alignment

Sequential guard: start this task only when `tasks/STATUS.md` shows no active task. This task has execution order `000` and must complete before task `000`.

## Goal

Resolve preimplementation contract inconsistencies that would otherwise send autonomous agents down conflicting implementation paths.

## Scope

- Align backlog-audit scope with every queued future task.
- Clarify Phase 2 stable mutator expectations versus preview mutator backlog.
- Clarify mutation-aware doctest summary and survivor AI context contracts.
- Clarify pre-task-041 pipeline artifact cutover wording.
- Define the `internal_error` report shape and its future schema-test ownership.
- Keep all edits to documentation, task metadata, schemas, and gap registries.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/068-preimplementation-contract-alignment.md`
- `tasks/025-autonomous-backlog-audit.md`
- `tasks/006-report-schema.md`
- `tasks/061-doctest-mutate-stabilization.md`
- `tasks/067-ai-doctest-survivor-assistance.md`
- `docs/ROADMAP.md`
- `docs/DOCTEST_SPEC.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/REPORT_FORMAT.md`
- `docs/VERIFICATION_PIPELINE.md`
- `docs/SEQUENTIAL_EXECUTION_POLICY.md`
- `.agents/workflows/task-plan.md`
- `docs/FAILURE_MODES.md`
- `schemas/report.v1.schema.json`
- `tests/coverage-gaps/failure_modes.v1.json`
- `tests/coverage-gaps/schemas.v1.json`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`

## Required tests

- Add a failing contract check only if this task changes validator behavior; otherwise preserve the pre-fix inconsistency evidence in the completion record.
- Run `python3 scripts/validate_task_system.py` before and after the contract edits.
- Run JSON syntax validation for edited JSON files.
- Run JSON fence validation for edited Markdown files.
- Run `git diff --check`.

## Acceptance criteria

- Task `025` can audit all currently queued future tasks, including inserted tasks `061` through `067`.
- `docs/ROADMAP.md` treats preview mutators as preview/backlog work, not required minimum-product implementation.
- `docs/DOCTEST_SPEC.md` defines exact `summary` and `summary.mutation` semantics for `zentinel doctest --mutate`.
- `docs/DOCTEST_AI_INTEGRATION.md` distinguishes the original doctest case from the mutation-aware report case for survivor AI evidence.
- Pipeline docs consistently state that durable pipeline artifacts are canonical only after task `041`; before then, equivalent evidence is recorded in status or completion summaries.
- `docs/REPORT_FORMAT.md`, `schemas/report.v1.schema.json`, task `006`, and the relevant gap registry row define `run.status = "internal_error"` consistently.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing zentinel behavior.
- Adding Zig source files or tests.
- Changing stable task IDs.
- Enabling preview mutators.
- Changing AI authority over deterministic correctness.

## Suggested implementation approach

1. Insert this prerequisite with execution order `000` and move project bootstrap to execution order `000.1`.
2. Patch the affected docs and task files narrowly.
3. Update only matching gap-registry rows for changed schema or failure-mode contracts.
4. Verify task metadata, JSON syntax, Markdown JSON examples, and whitespace.
5. Mark this task complete and leave task `000` as the next task.

## Dogfooding implications

This task removes contract ambiguity before dogfoodable behavior exists. No dogfood run is expected.

## Follow-up tasks

- None predefined.
