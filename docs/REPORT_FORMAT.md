# Report Format

zentinel reports are deterministic artifacts. They must support human diagnosis, CI gating, editor integrations, and AI advisory flows without changing meaning between runs.

## Report Types

| Format | Purpose |
| --- | --- |
| text | Default terminal output for humans. |
| json | Stable machine-readable report. |
| jsonl | Streaming or large-run processing. |
| junit | CI test-report integration for killed/survived summaries. |

JSON is the canonical report format.

## JSON Envelope

```json
{
  "schema_version": "zentinel.report.v1",
  "run": {
    "id": "run_01hr7pc9qdyj2f3d7z7me3x1rk",
    "status": "completed",
    "error": null,
    "zentinel_version": "0.1.0",
    "zig_version": "latest-stable",
    "command": "zentinel run",
    "config_hash": "sha256:4b7d8e3f0a2c9b1d6e5f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5",
    "project_root": "<project>",
    "started_at": "<normalized>",
    "duration_ms": 0
  },
  "baseline": {
    "status": "passed",
    "commands": [
      {
        "command": {
          "original": "zig build test",
          "argv": ["zig", "build", "test"],
          "cwd": "<project>",
          "environment_policy": "minimal",
          "shell": false
        },
        "phase": "baseline",
        "status": "passed",
        "exit_code": 0,
        "timed_out": false,
        "duration_ms": 0,
        "evidence": {
          "stdout_excerpt": "",
          "stderr_excerpt": "",
          "failure_summary": ""
        },
        "skip_reason": null
      }
    ]
  },
  "diagnostics": {
    "cache": {
      "enabled": false,
      "mode": "disabled",
      "hits": 0,
      "misses": 0
    }
  },
  "summary": {
    "total": 0,
    "killed": 0,
    "survived": 0,
    "compile_error": 0,
    "compiler_crash": 0,
    "timeout": 0,
    "skipped": 0,
    "invalid": 0
  },
  "mutants": []
}
```

`run.id`, `started_at`, and `duration_ms` are observation metadata. They may be real in normal reports, but snapshots, cache comparisons, dogfood repeated-run checks, and release acceptance checks must normalize them before comparing reports.

All deterministic fields outside observation metadata must match for the same repository content, config, Zig version, backend, safety mode, command, and selected tests.

`diagnostics.cache` is the only cache-related field in report v1. It is optional until cache behavior exists, but any report that records cache behavior must use this object instead of adding ad hoc top-level fields. Cached/uncached report comparisons may ignore only `diagnostics.cache` and observation metadata.

`run.status` is the run-level outcome:

| Status | Meaning |
| --- | --- |
| `completed` | Baseline completed and mutant execution/reporting reached a deterministic terminal state. |
| `baseline_failed` | Baseline tests failed before any mutant execution. |
| `internal_error` | zentinel could not produce normal mutant results because it violated an internal contract or hit an unrecoverable implementation error; this is a tool failure, not a mutant result. |

`summary` counts only entries in `mutants`. For `run.status = baseline_failed`, `baseline.status` is `failed`, `mutants` is empty unless a future schema explicitly supports partial execution, and all summary counts are zero.

`run.error` is required in every report. For `run.status = completed` and `run.status = baseline_failed`, it is `null`. For `run.status = internal_error`, it is a closed object with required `code`, `message`, and `phase` fields plus an optional bounded `details` array of strings. The `code` must be a stable documented error code such as `ZNTL_INTERNAL_INVARIANT`; generic internal-error text without a stable code violates D-302. `run.error` must be derived from deterministic tool evidence and must not contain AI-generated explanation.

For `run.status = internal_error`, `mutants` may be empty or may contain a deterministic partial prefix that still validates as ordinary mutant entries. `summary` counts only the `mutants` entries present in the report. If the internal error occurs before baseline command evidence exists, `baseline.status` is `not_run` and `baseline.commands` is empty. Otherwise, `baseline.status` remains the observed deterministic baseline state.

Report v1 does not support skipping the baseline. `baseline.status = "not_run"` is allowed only for `run.status = internal_error` before baseline command evidence exists; it is not a cache-backed baseline skip. Any future cache-backed baseline skip requires a new documented proof contract before a writer may emit it.

## Mutant Entry

`id` is the durable mutant reference. `display_id` is a report-local compact index assigned after canonical sorting; it is valid as a short selector only with the report that produced it.

```json
{
  "id": "m_01hr7p6h0v2fj3drdzt9k2a0xe",
  "display_id": 42,
  "backend": "ast",
  "backend_stability": "stable",
  "operator": "comparison_boundary",
  "operator_stability": "stable",
  "file": "src/range.zig",
  "span": {
    "byte_start": 310,
    "byte_end": 312,
    "line_start": 12,
    "column_start": 13,
    "line_end": 12,
    "column_end": 15
  },
  "original": ">=",
  "replacement": ">",
  "diff": [
    "- if (idx >= items.len) return error.OutOfBounds;",
    "+ if (idx > items.len) return error.OutOfBounds;"
  ],
  "expected_compile": "compiles",
  "result": {
    "status": "survived",
    "mode": "Debug",
    "commands": [
      {
        "command": {
          "original": "zig test src/range.zig",
          "argv": ["zig", "test", "src/range.zig"],
          "cwd": "<project>",
          "environment_policy": "minimal",
          "shell": false
        },
        "phase": "mutant",
        "status": "passed",
        "exit_code": 0,
        "timed_out": false,
        "duration_ms": 15,
        "evidence": {
          "stdout_excerpt": "",
          "stderr_excerpt": "",
          "failure_summary": ""
        },
        "skip_reason": null
      }
    ],
    "phase": "mutant",
    "duration_ms": 15,
    "evidence": {
      "stdout_excerpt": "",
      "stderr_excerpt": "",
      "failure_summary": ""
    }
  },
  "test_selection": {
    "strategy": "same_file",
    "selected": [
      {
        "file": "src/range.zig",
        "name": "get returns element",
        "line": 18
      }
    ],
    "commands": [
      "zig test src/range.zig"
    ],
    "fallback_used": false
  },
  "advisory": {
    "equivalent_risks": [
      "tests do not exercise equality case"
    ],
    "ai": null
  }
}
```

## Result Status

| Status | Meaning |
| --- | --- |
| `killed` | Selected tests failed for the mutant after baseline passed. |
| `survived` | Selected tests passed for the mutant. |
| `compile_error` | Mutated project failed to compile. |
| `compiler_crash` | Zig compiler process crashed, panicked, or terminated abnormally while compiling a syntactically valid mutant. |
| `timeout` | Test command exceeded configured timeout. |
| `skipped` | Mutant was not executed for a deterministic documented reason. |
| `invalid` | zentinel generated an invalid patch or violated a backend contract. |

Baseline failure is a run-level state (`run.status = baseline_failed`), not a mutant result status.

`compiler_crash` is distinct from `compile_error` and `invalid`. A normal Zig diagnostic for a mutated project is `compile_error`; a zentinel-generated malformed patch or backend contract violation is `invalid`; an abnormal Zig compiler panic/crash while compiling an otherwise syntactically valid mutant is `compiler_crash` with command evidence and bounded compiler output.

## Command Evidence

Every command recorded in `baseline.commands` or a mutant `result.commands` must use the same structured command object:

```json
{
  "original": "zig test src/range.zig",
  "argv": ["zig", "test", "src/range.zig"],
  "cwd": "<project>",
  "environment_policy": "minimal",
  "shell": false
}
```

`original` is the configured or selected command text for diagnosis. `argv` is the parsed execution shape from `src/command.zig`; `argv[0]` must be non-empty. Stable Phase 1 execution must set `environment_policy` to `minimal` and `shell` to `false`.

Each command result records `phase`, `status`, `exit_code`, `timed_out`, `duration_ms`, bounded evidence, and `skip_reason`. Entries under `baseline.commands` must use `phase = "baseline"` and cannot be skipped in report v1. Entries under mutant `result.commands` must use `phase = "mutant"`. Mutant fail-fast records commands that were not executed with `status = "skipped"` and a non-empty deterministic `skip_reason`; executed commands use `skip_reason = null`.

## Stability Fields

`backend_stability` describes the backend that produced the mutant. Valid values are `stable` and `experimental`; the AST backend is stable, while ZIR and AIR are experimental until promoted by a future ADR and release criteria.

`operator_stability` describes the mutator operator. Valid values are `stable`, `preview`, and `experimental` as defined by `docs/MUTATOR_SPEC.md`. Preview operators may appear only when explicitly enabled by config or task scope; they are never part of the default stable minimum product.

## Text Output Style

Default text output should prioritize actionable survivors:

```text
survived 42 comparison_boundary src/range.zig:12
  - if (idx >= items.len) return error.OutOfBounds;
  + if (idx > items.len) return error.OutOfBounds;
  selected tests passed: zig test src/range.zig
  likely focus: boundary where idx == items.len
```

Summary should be compact:

```text
1 mutant: 0 killed, 1 survived
```

Avoid making percentage score the headline.

## JUnit Output

JUnit output is a CI integration format derived from the same canonical report data. It is not the canonical mutation report.

The default JUnit mode is diagnostic:

- emit one `<testsuite name="zentinel.mutation">`
- emit one `<testcase>` per mutant in canonical report order
- set each testcase `classname` to `zentinel.mutant`
- set each testcase `name` to `<display_id> <operator> <file>:<line_start>`
- add testcase `<properties>` for `mutant_id`, `backend`, `backend_stability`, `operator`, `operator_stability`, `status`, `phase`, command count, and each command's original text, argv, cwd, environment policy, shell flag, command status, and skip reason
- write bounded deterministic evidence to `<system-out>` or `<system-err>` with normalized durations in snapshots

Status mapping in diagnostic mode:

| Status | JUnit representation |
| --- | --- |
| Mutant `killed` | Passing testcase with `status=killed` property. |
| Mutant `compile_error` | Passing testcase with `status=compile_error` property. |
| Mutant `compiler_crash` | Testcase with `<error type="zentinel.compiler_crash">`. |
| Mutant `survived` | Passing testcase with `status=survived` property. |
| Mutant `skipped` | Testcase with `<skipped message="deterministically skipped"/>`. |
| Mutant `timeout` | Testcase with `<error type="zentinel.timeout">`. |
| Mutant `invalid` | Testcase with `<error type="zentinel.invalid">`. |
| Run `baseline_failed` | A single testcase named `baseline` with `<error type="zentinel.baseline_failed">`; mutant testcases are omitted when no mutants ran. |

When a future strict CI option such as `--fail-on-survivors` is enabled, survived mutants additionally emit `<failure type="zentinel.survived">`. This is the only mode where survivors are represented as JUnit failures. The diagnostic default must not claim that the project unit tests failed when the mutation report only shows surviving mutants.

Suite counts are derived from emitted testcases:

- `tests`: testcase count
- `failures`: survived testcase count only in strict survivor-failing mode
- `errors`: timeout, compiler_crash, invalid, and baseline_failed testcase count
- `skipped`: skipped testcase count
- `time`: normalized in snapshots and never used for deterministic comparisons

## Ordering

Reports must sort mutants by canonical candidate ordering:

1. file
2. byte start
3. byte end
4. operator
5. replacement
6. backend

Summary counts are derived from the sorted entries.

## Repeated-Run Comparison

Repeated-run comparisons use the canonical JSON report after normalizing:

- `run.id`
- `run.started_at`
- `run.duration_ms`
- `baseline.commands[*].duration_ms`
- per-command and per-mutant duration fields

No other deterministic result, candidate, ordering, schema, or evidence field may differ without an explicit documented reason.

## Schema Compatibility

Breaking report changes require:

- new `schema_version`
- migration note in docs
- contract tests for both old reader behavior, if supported, and new writer behavior

Advisory AI fields may grow under `advisory.ai` without changing deterministic result semantics.
