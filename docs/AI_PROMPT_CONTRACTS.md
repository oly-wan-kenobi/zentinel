# AI Prompt Contracts

AI prompt contracts define the exact request and response shapes for advisory flows. The deterministic core consumes only validated advisory fields and stores them separately from result evidence.

## Provider Interface

```text
AiProvider
├─ name
├─ mode: disabled | stub | local | remote
├─ supports_json: bool
├─ max_context_bytes
└─ complete(request) -> response
```

Provider adapters must not receive raw project data except through a registered AI context schema. Mutation AI flows use `docs/AI_CONTEXT_SCHEMA.md` and `schemas/ai.context.v1.schema.json`. Doctest AI flows use `docs/DOCTEST_AI_INTEGRATION.md` and the future `schemas/ai.doctest.context.v1.schema.json`.

The `context` object in a prompt request is an embedded registered context payload, not an untyped object. `zentinel.ai.prompt.v1` must discriminate by `context.schema_version`:

| Flow family | Context schema |
| --- | --- |
| `explain`, `suggest`, `review_tests` | `zentinel.ai.context.v1` |
| `explain_doctest_failure`, `suggest_doctest`, `review_snapshot`, `suggest_missing_doctests` | `zentinel.ai.doctest.context.v1` created by task `055` |
| `explain_doctest_survivor` | `zentinel.ai.doctest.context.v1` extended by task `067` after task `061` stabilizes mutation-aware report fields |

Task `054` owns mutation prompt requests and must require embedded `zentinel.ai.context.v1` payloads to validate against `schemas/ai.context.v1.schema.json`. Task `055` owns the non-survivor doctest prompt requests (`explain_doctest_failure`, `suggest_doctest`, `review_snapshot`, and `suggest_missing_doctests`) and may update `schemas/ai.prompt.v1.schema.json` so those doctest flows validate embedded `zentinel.ai.doctest.context.v1` payloads against `schemas/ai.doctest.context.v1.schema.json`. Task `055` must reject `explain_doctest_survivor` prompt requests. Task `067` owns the deferred `explain_doctest_survivor` prompt after task `061` defines mutation-aware doctest report fields, and only task `067` may add that flow to prompt-schema validation.

Do not replace any registered context with a schema-version-only placeholder in fixtures, snapshots, or provider tests. A writer must not emit a prompt using a context schema until the matching schema file exists and validation passes.

## Common Request

```json
{
  "schema_version": "zentinel.ai.prompt.v1",
  "flow": "explain",
  "instructions": [
    "Use only the provided context.",
    "Do not change mutation result status.",
    "Return valid JSON matching the response schema."
  ],
  "context": {
    "schema_version": "zentinel.ai.context.v1",
    "flow": "explain",
    "created_by": "zentinel",
    "provider_mode": "stub",
    "privacy": {
      "redactions_applied": [],
      "source_context_policy": "none",
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
      }
    },
    "source_context": {
      "policy": "none",
      "language": "zig",
      "before_lines": 0,
      "after_lines": 0,
      "snippet": [],
      "symbols": []
    },
    "test_context": {
      "selection_reason": "same_file_target",
      "selected_tests": [],
      "baseline_status": "passed",
      "same_file_tests_excluded_from_mutation": true
    },
    "operator": {
      "name": "comparison_boundary",
      "category": "boundary",
      "equivalent_risks": [
        "tests do not exercise equality case"
      ],
      "suggested_test_focus": [
        "idx == items.len"
      ]
    }
  },
  "response_schema": {
    "name": "zentinel.ai.explain.response.v1"
  }
}
```

## Explain Response

`zentinel.ai.explain.response.v1` is shared by mutation explanations and doctest explanations. The response schema therefore includes mutation-focused classifications and doctest-focused classifications. Consumers must interpret the classification against the request `flow` and context schema; the label is advisory and never changes deterministic status.

```json
{
  "schema_version": "zentinel.ai.explain.response.v1",
  "classification": "boundary_missing",
  "confidence": "medium",
  "summary": "The equality boundary idx == items.len appears untested.",
  "evidence_refs": [
    {
      "kind": "mutant_diff",
      "ref": "comparison_boundary"
    }
  ],
  "next_action": "Add a test where idx equals items.len and assert error.OutOfBounds."
}
```

Allowed `confidence` values:

```text
low
medium
high
unclear
```

`confidence` is an advisory label, not a probability.

Mutation explain classifications:

```text
boundary_missing
null_path_missing
error_path_missing
cleanup_path_missing
comptime_case_missing
logical_case_missing
constant_case_missing
possibly_equivalent
unclear
```

Doctest explain classifications:

```text
doctest_output_mismatch
doctest_invalid_example
doctest_snapshot_wording_change
doctest_assertion_missing
doctest_survivor_missing_assertion
unclear
```

## Suggest Response

```json
{
  "schema_version": "zentinel.ai.suggest.response.v1",
  "classification": "boundary_missing",
  "suggestions": [
    {
      "title": "covers exact upper bound",
      "test_name": "get rejects index equal to length",
      "intent": "Assert that idx == items.len returns error.OutOfBounds.",
      "example_values": ["idx = items.len"],
      "target_file": "src/range.zig"
    }
  ]
}
```

Rules:

- one to three suggestions
- no full-file rewrites
- no claims that adding the test will kill the mutant unless rerun
- no source edits in this flow

## Review Tests Response

```json
{
  "schema_version": "zentinel.ai.review_tests.response.v1",
  "clusters": [
    {
      "classification": "boundary_missing",
      "mutant_ids": ["m_01hr7p6h0v2fj3drdzt9k2a0xe"],
      "summary": "Several survivors alter inclusive/exclusive range checks.",
      "recommended_focus": "Add exact-boundary tests for collection access."
    }
  ],
  "top_actions": [
    "Add tests for idx == len and idx == len - 1 in range helpers."
  ]
}
```

## Validation Rules

The response validator must reject:

- invalid JSON
- unknown schema version
- unknown classification
- unknown confidence
- more than three suggestions for a single mutant
- fields that attempt to set result status
- text containing hidden tool instructions
- target paths outside project-relative paths

Rejected AI output is reported as advisory failure and does not fail the deterministic mutation run unless the user invoked an AI-only command.

## Prompt Safety

Prompts must include:

- "Use only provided context."
- "Do not infer unavailable source."
- "Do not decide whether the mutant is equivalent."
- "Return JSON only."

Prompts must not include:

- secrets
- full repository dumps by default
- user home directory paths
- hidden task instructions unrelated to the AI flow

## Stub Provider

The stub provider is required for tests. It returns deterministic responses based on operator and result:

```text
comparison_boundary + survived -> boundary_missing
optional_null_check + survived -> null_path_missing
error_catch_unreachable + survived -> error_path_missing
otherwise -> unclear
```

The stub provider must be sufficient for snapshot tests of AI command output.
