# 006 Report Schema

Sequential guard: start this task only after task 005 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Add typed report data structures and JSON serialization matching `docs/REPORT_FORMAT.md` without generating real mutants yet.

## Scope

- Define report envelope, summary, mutant entry, result, span, backend stability, operator stability, and test selection structs.
- Serialize deterministic JSON.
- Add schema-oriented tests and snapshots.

## Files allowed to modify

- `schemas/report.v1.schema.json`
- `src/report.zig`
- `test/report_schema_test.zig`
- `test/snapshots/report_minimal.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/runner.zig`
- `src/ast_backend.zig`
- `src/ai/**`

## Required tests

- Add a failing serialization snapshot for a minimal report.
- Add a failing test for sorted mutant entries.
- Add a failing schema test that a report has a run-level `status`, a `baseline` object, and mutant summary counts derived only from `mutants`.
- Add a failing schema test that `run.status = baseline_failed` requires `baseline.status = failed`, zero summary counts, and an empty `mutants` array.
- Add a failing schema test that a baseline command with `status = "timeout"` is valid only under the baseline failure shape with `run.status = baseline_failed`, `baseline.status = failed`, `timed_out = true`, `exit_code = null`, empty `mutants`, and zero summary counts.
- Add a failing schema test that `run.status = completed` requires `baseline.status = passed`.
- Add a failing schema test that `run.status = internal_error` requires a closed `run.error` object with stable `code`, `message`, and `phase`, allows an empty or schema-valid partial `mutants` array, and keeps summary counts derived only from present `mutants`.
- Add a failing schema test that `run.error` is `null` for `completed` and `baseline_failed`, and that `baseline.status = not_run` with empty `baseline.commands` is accepted only for `internal_error` before baseline command evidence exists.
- Add a failing schema test that `baseline.commands` is non-empty and that each command entry has structured evidence fields. Successful quiet commands may have empty stdout, stderr, and failure summaries.
- Add a failing schema test that baseline command results require `phase = "baseline"`, `status`, and `skip_reason = null`; mutant results require a `commands` array whose entries use `phase = "mutant"`; skipped mutant commands require a non-empty deterministic `skip_reason`; and `baseline.status` rejects skipped baselines in report v1.
- Add a failing schema test that command evidence uses `original`, a parsed `argv` with non-empty `argv[0]`, `cwd`, `environment_policy = "minimal"`, and `shell = false` instead of a display-only command string.
- Add a failing schema test that mutant results reject the legacy single `command`, `exit_code`, and `timed_out` result shape.
- Add a failing schema test that optional cache diagnostics must appear only under `diagnostics.cache`.
- Add a failing schema test that `test_selection` requires `strategy`, `selected`, `commands`, and `fallback_used` and rejects unknown fields.
- Add a failing test that `backend_stability` and `operator_stability` are distinct fields and validate their separate enum values.
- Add a failing test that advisory AI fields cannot overwrite result fields.
- Run `zig build test`.

## Acceptance criteria

- JSON report matches documented schema names and status values.
- Baseline failure is represented as `run.status = baseline_failed`, not as a mutant result status.
- Internal tool failure is represented as `run.status = internal_error` with deterministic `run.error` evidence, not as a mutant result status or advisory AI text.
- Mutant entries serialize in deterministic order.
- Summary counts are derived from entries.
- No command runs or mutant generation are implemented.

## Non-goals

- Text renderer.
- JUnit renderer.
- AI prompt schema.
- Real execution evidence collection.

## Suggested implementation approach

1. Define enums for result status, backend, backend stability, and operator stability.
2. Make summary computation pure.
3. Keep JSON key ordering stable.
4. Use snapshots with normalized volatile fields.

## Dogfooding implications

Report serialization is a high-value dogfood target because users and AI flows depend on it.

## Follow-up tasks

- `tasks/007-mutant-model.md`
