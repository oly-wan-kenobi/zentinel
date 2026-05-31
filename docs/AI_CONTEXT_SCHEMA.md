# AI Context Schema

This document defines the normalized JSON context zentinel may pass to AI providers. The schema is deterministic, privacy-filtered, and advisory-only.

## Envelope

This example is a minimal valid payload shape. Do not use empty placeholder objects in fixtures or snapshots; every nested object must satisfy `schemas/ai.context.v1.schema.json`.

```json
{
  "schema_version": "zentinel.ai.context.v1",
  "flow": "explain",
  "created_by": "zentinel",
  "provider_mode": "stub",
  "privacy": {
    "redactions_applied": [],
    "source_context_policy": "minimal",
    "remote_allowed": false
  },
  "project": {
    "name": "example",
    "root_label": "<project>",
    "zig_version": "0.16.0",
    "zentinel_version": "0.1.0"
  },
  "mutant": {
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
    "expected_compile": "compiles"
  },
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
        "failure_kind": "none",
        "duration_ms_normalized": "<duration>",
        "evidence": {
          "stdout_excerpt": "",
          "stderr_excerpt": "",
          "failure_summary": ""
        },
        "skip_reason": null
      }
    ],
    "phase": "mutant",
    "duration_ms_normalized": "<duration>",
    "evidence": {
      "stdout_excerpt": "",
      "stderr_excerpt": "",
      "failure_summary": ""
    },
    "skip_reason": null
  },
  "source_context": {
    "policy": "minimal",
    "language": "zig",
    "before_lines": 4,
    "after_lines": 4,
    "snippet": [
      "pub fn get(items: []const u8, idx: usize) !u8 {",
      "    if (idx >= items.len) return error.OutOfBounds;",
      "    return items[idx];",
      "}"
    ],
    "symbols": [
      {
        "kind": "function",
        "name": "get",
        "line": 10
      }
    ]
  },
  "test_context": {
    "selection_reason": "same_file_target",
    "selected_tests": [
      {
        "name": "get returns element",
        "file": "src/range.zig",
        "line": 18
      }
    ],
    "baseline_status": "passed",
    "same_file_tests_excluded_from_mutation": true
  },
  "operator": {
    "name": "comparison_boundary",
    "category": "boundary",
    "equivalent_risks": [
      "boundary value not reachable",
      "tests do not exercise equality case"
    ],
    "suggested_test_focus": [
      "idx == items.len",
      "idx == items.len - 1"
    ]
  }
}
```

## Flow Values

Allowed `flow` values:

```text
explain
suggest
review_tests
```

## Mutant Object

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
  "expected_compile": "compiles"
}
```

`id` is the canonical mutant reference. `display_id` is included only for human-readable correlation with the selected report and must not be treated as durable. `backend_stability` describes only the backend (`stable` or `experimental`). `operator_stability` describes the mutator operator (`stable`, `preview`, or `experimental`) and follows `docs/MUTATOR_SPEC.md`.

`backend_version` is intentionally omitted from AI context v1. It is internal identity/cache evidence and must not be sent to AI providers without a versioned schema change.

## Result Object

```json
{
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
      "failure_kind": "none",
      "duration_ms_normalized": "<duration>",
      "evidence": {
        "stdout_excerpt": "",
        "stderr_excerpt": "",
        "failure_summary": ""
      },
      "skip_reason": null
    }
  ],
  "phase": "mutant",
  "duration_ms_normalized": "<duration>",
  "evidence": {
    "stdout_excerpt": "",
    "stderr_excerpt": "",
    "failure_summary": ""
  },
  "skip_reason": null
}
```

Allowed `status` values:

```text
killed
survived
compile_error
compiler_crash
timeout
skipped
invalid
```

AI receives status as read-only evidence.

`result.skip_reason` is required and non-null when `result.status = "skipped"`; all other result statuses set it to `null`.

The `commands` array mirrors mutant command results from the canonical report schema with snapshot-normalized durations. Each command entry requires `failure_kind`. Each entry includes the original display command, parsed argv with non-empty `argv[0]`, normalized cwd label, `environment_policy: "minimal"`, `shell: false`, `phase: "mutant"`, command status, `failure_kind`, exit evidence, and `skip_reason`. AI mutant context uses `phase: "mutant"` because baseline failures are represented at report run level instead of as mutant results.

`stdout_excerpt` and `stderr_excerpt` are capped at 4096 UTF-8 bytes before AI context construction, matching `docs/SANDBOX_SECURITY.md` and the report command-evidence bound. Truncation must occur at a safe character boundary so emitted JSON remains valid UTF-8.

## Source Context

```json
{
  "policy": "minimal",
  "language": "zig",
  "before_lines": 4,
  "after_lines": 4,
  "snippet": [
    "pub fn get(items: []const u8, idx: usize) !u8 {",
    "    if (idx >= items.len) return error.OutOfBounds;",
    "    return items[idx];",
    "}"
  ],
  "symbols": [
    {
      "kind": "function",
      "name": "get",
      "line": 10
    }
  ]
}
```

## Test Context

```json
{
  "selection_reason": "same_file_target",
  "selected_tests": [
    {
      "name": "get returns element",
      "file": "src/range.zig",
      "line": 18
    }
  ],
  "baseline_status": "passed",
  "same_file_tests_excluded_from_mutation": true
}
```

Allowed `baseline_status` values are `passed`, `failed`, and `unknown`. Report v1 does not allow skipped baselines, so AI context must not emit `skipped` for baseline status.

## Operator Context

```json
{
  "name": "comparison_boundary",
  "category": "boundary",
  "equivalent_risks": [
    "boundary value not reachable",
    "tests do not exercise equality case"
  ],
  "suggested_test_focus": [
    "idx == items.len",
    "idx == items.len - 1"
  ]
}
```

## Privacy Requirements

Before building AI context, zentinel must:

- normalize absolute paths to project-relative paths
- remove environment variables
- redact configured secret patterns (labels) and value-shaped secrets (values)
- cap source context line counts
- omit unrelated files
- mark whether remote transmission is allowed

If redaction fails, the AI flow must fail closed.

### Redaction Guarantee (labels vs values)

Redaction (`src/ai/redaction.zig`) operates at two levels, both applied to every evidence excerpt before it enters the context:

- **Configured label patterns.** The `ai.redact_patterns` from config (default `(?i)api[_-]?key` and `(?i)token`) mask known secret *labels*. The supported pattern subset is intentionally tiny — an optional `(?i)` case-insensitive flag, literal runs, and the single `[_-]?` optional-separator construct — so it stays auditable. An unsupported or malformed configured pattern is rejected and the AI flow **fails closed** (`error.RedactionFailed`); it is never silently ignored. A label pattern masks only the label text, not the value that follows it.
- **Built-in value shapes.** Independently of configuration, a fixed set of matchers redacts the secret *values* themselves by shape: GitHub tokens (`ghp_`/`gho_`/`ghu_`/`ghs_`/`ghr_`/`github_pat_`), AWS access key ids (`AKIA`/`ASIA`), Anthropic API keys (`sk-ant-`), JSON Web Tokens, and PEM private-key blocks. This catches a credential that carries no configured label, or the value immediately after one.

Each match — label or value — is replaced by the fixed marker `[REDACTED]`. `privacy.redactions_applied` lists only the configured label patterns that matched (verbatim, in configuration order); the built-in value filter always runs and is not enumerated there. Redaction is applied before the 4096 UTF-8 byte excerpt cap, so truncation cannot split a secret and leak a tail.

The value filter is a targeted credential matcher for the shapes above, not a general-purpose data-loss-prevention engine; configured patterns and the fail-closed contract remain the primary control.

## Deterministic Ordering

Arrays must be sorted by stable keys:

- `selected_tests`: file, line, name
- `symbols`: line, kind, name
- `result.commands`: canonical report command order
- `equivalent_risks`: spec order
- `suggested_test_focus`: spec order

This allows prompt snapshots to be stable.
