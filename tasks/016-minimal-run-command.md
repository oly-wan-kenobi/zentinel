# 016 Minimal Run Command

Sequential guard: start this task only after task 015 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement `zentinel run` for a single-threaded Phase 1 flow over configured files and stable AST mutators.

## Scope

- Load config.
- Validate Zig version.
- Build the project model from config: source roots, include/exclude globs, and the configured baseline/test command.
- Discover eligible source files from the configured include/exclude rules rather than a hardcoded fixture file list.
- Run baseline tests.
- Generate Phase 1 AST candidates over the discovered source files.
- Support Phase 1 run options `--operator <name>`, `--mutant <id>`, `--fail-on-survivors`, `--report <text|json>`, and `--output <path>`.
- Execute mutants serially.
- Write JSON report and text summary.

## Files allowed to modify

- `src/cli.zig`
- `src/main.zig`
- `src/run_command.zig`
- `src/project_model.zig`
- `src/report.zig`
- `src/ast_backend.zig`
- `test/run_command_test.zig`
- `test/project_model_test.zig`
- `test/fixtures/run_command/**`
- `test/snapshots/run_command_*.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/ai/**`
- `src/worker_pool.zig`
- `src/cache.zig`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `src/mutators/optional.zig`

## Required tests

- Add a failing test proving eligible source files are discovered from config include/exclude globs over a fixture project rather than a hardcoded file list.
- Add a failing end-to-end fixture test for one killed mutant.
- Add a failing end-to-end fixture test for one survived mutant.
- Add a failing test for baseline failure exit behavior.
- Add failing CLI tests for `--operator <name>` filtering, `--mutant <id>` single-mutant selection, `--fail-on-survivors` exit code `1`, and `--output <path>` report writing.
- Add a failing CLI test proving Explicit `--output <path>` inherits the same project-root restriction as `report.output_dir`.
- Add a failing CLI test proving `run.jobs > 1` is rejected before task 050 instead of being silently ignored.
- Add a failing JSON report snapshot proving baseline failure sets `run.status = baseline_failed`, records baseline command evidence, emits no mutant result with `baseline_failed`, and leaves summary counts at zero.
- Add a failing JSON report snapshot proving baseline timeout maps to `run.status = baseline_failed`, `baseline.status = failed`, timed-out baseline command evidence, empty `mutants`, and zero summary counts.
- Add a failing JSON report snapshot proving a completed run sets `run.status = completed`, includes deterministic mutant entries, and derives summary counts from those entries.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `zentinel run` works for small fixture projects.
- The project model and the set of mutated source files are derived from config include/exclude rules; `zentinel run` is not limited to a single hardcoded fixture file.
- Reports include deterministic mutant entries and summary counts.
- Baseline failure stops mutant execution and is represented as a run-level status with structured baseline command evidence.
- Baseline timeout follows the same run-level baseline failure path and exits with code `3`.
- `--fail-on-survivors` changes only process exit status, not deterministic report fields.
- `--operator <name>`, `--mutant <id>`, and `--output <path>` are implemented by the run command rather than left as documented-only options.
- Explicit `--output <path>` inherits the same project-root restriction as `report.output_dir`.
- Output remains concise and survivor-focused.

## Non-goals

- Parallel execution.
- Cache.
- AI advisory output.
- Experimental backends.

## Suggested implementation approach

1. Wire existing modules with minimal orchestration.
2. Keep execution serial and easy to debug.
3. Use small fixture projects and discover their source files via config include/exclude globs, rather than hardcoding file paths or scanning the whole repository.
4. Keep the project model config-driven (source roots, globs, baseline command); full `build.zig` graph analysis is out of scope here.
5. Avoid adding configuration options not already documented.

## Dogfooding implications

This is the first task after which fixture-only dogfooding can run in a meaningful way.

## Follow-up tasks

- `tasks/017-list-mutants-command.md`
