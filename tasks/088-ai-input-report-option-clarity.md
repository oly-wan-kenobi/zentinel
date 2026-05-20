# 088 AI Input Report Option Clarity

Sequential guard: start this task only after task `087` is complete and `tasks/status.json` names `088` as the next queued task. No later-order task may begin until this task is complete.

## Goal

Remove CLI ambiguity by making advisory AI commands read deterministic reports through `--input-report <path>` instead of overloading mutation-run `--report <format>`.

## Scope

- Update `docs/CLI_SPEC.md` so AI commands use `--input-report <path>`.
- Update doctest AI docs and doctest mutation strategy wording to reserve `--input-report` for advisory commands that read existing reports.
- Update task `054` and task `055` CLI test requirements to use `--input-report`.
- Add validator guardrails rejecting AI report-input wording that uses `--report <path>`.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/088-ai-input-report-option-clarity.md`
- `tasks/000-project-bootstrap.md`
- `tasks/054-ai-advisory-commands.md`
- `tasks/055-ai-doctest-assistance.md`
- `docs/CLI_SPEC.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/DOCTEST_MUTATION_STRATEGY.md`
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

- Add a failing validator guardrail requiring `docs/CLI_SPEC.md` to define `--input-report <path>` for AI report inputs.
- Add a failing validator guardrail rejecting `--report <path>` in AI command contracts.
- Add failing validator guardrails requiring task `054` and task `055` to use `--input-report`.
- Run `python3 scripts/validate_task_system.py` and record the expected failure before updating docs and task wording.
- Run `python3 scripts/validate_task_system.py` after the contracts are aligned.

## Acceptance criteria

- Mutation runs still use `zentinel run --report <text|json|jsonl|junit>`.
- Advisory AI commands use `--input-report <path>` for existing deterministic reports.
- Task `054` and task `055` require tests for `--input-report`.
- `python3 scripts/validate_task_system.py` passes.

## Non-goals

- Implementing AI commands.
- Changing report formats.
- Changing doctest output selection.

## Suggested implementation approach

1. Add validator checks first and confirm they fail on current AI `--report <path>` wording.
2. Update only the AI report-input docs and task requirements.
3. Complete this pre-bootstrap clarity task and leave project bootstrap as the next dependency-ready task.

## Dogfooding implications

No runtime behavior exists yet. This task keeps future AI/doctest dogfood scripts from confusing report format selection with report input selection.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
