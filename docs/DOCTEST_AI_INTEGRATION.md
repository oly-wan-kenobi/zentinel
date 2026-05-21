# Doctest AI Integration

AI can make doctest failures and documentation survivors easier to understand. It remains advisory only.

## Allowed AI Flows

| Flow | User-facing CLI command | Owner |
| --- | --- | --- |
| `explain_doctest_failure` | `zentinel doctest explain <case-ref>` | task `055` |
| `suggest_doctest` | `zentinel doctest suggest <doc-path>` | task `055` |
| `review_snapshot` | `zentinel doctest review-snapshot <case-ref>` | task `055` |
| `suggest_missing_doctests` | `zentinel doctest suggest-missing [--file <doc-path>]` | task `055` |
| `explain_doctest_survivor` | `zentinel doctest explain-survivor <survivor-ref>` | task `067`, after task `061` defines stable doctest mutation report fields |

## CLI Surface

Doctest AI exposes user-facing CLI subcommands so autonomous agents can invoke and test the flows directly:

```bash
zentinel doctest explain <case-ref> [--input-report <path>] [--ai-provider <disabled|stub|local|remote>]
zentinel doctest suggest <doc-path> [--input-report <path>] [--ai-provider <disabled|stub|local|remote>]
zentinel doctest review-snapshot <case-ref> [--input-report <path>] [--ai-provider <disabled|stub|local|remote>]
zentinel doctest suggest-missing [--file <doc-path>] [--input-report <path>] [--ai-provider <disabled|stub|local|remote>]
zentinel doctest explain-survivor <survivor-ref> [--input-report <path>] [--ai-provider <disabled|stub|local|remote>]
```

`explain` resolves `<case-ref>` against the selected deterministic doctest report, defaulting to `zig-out/zentinel/doctest/report.json` when `--input-report` is omitted. `<case-ref>` may be a durable `dt_...` doctest case ID or a source ref such as `docs/CLI_SPEC.md:47[:help-output]`; source refs are selectors only, resolve against the case anchor line, and must resolve to one case in the selected report.

`suggest` accepts a project-relative documentation path and does not require a report. When `--input-report` is provided, the report is optional context and must be validated before use. `suggest-missing` scans deterministic public-docs metadata and optionally narrows candidates with `--file <doc-path>`. These commands are advisory-only and must not edit documentation, snapshots, or deterministic doctest reports.

`review-snapshot` resolves `<case-ref>` like `explain` and requires the selected report. It is valid only for a case whose report entry contains exact `case.result.snapshot` evidence. It returns `zentinel.ai.doctest.snapshot_review.response.v1` and must not approve or apply snapshot updates.

`explain-survivor` resolves `<survivor-ref>` against a mutation-aware doctest report produced by `zentinel doctest --mutate`. It is intentionally deferred to task `067` so task `055` does not speculate about mutation-aware report fields before task `061` defines them.

An unresolved `<survivor-ref>` fails with `ZNTL_DOCTEST_SURVIVOR_NOT_FOUND`.

`zentinel doctest explain` reuses `zentinel.ai.explain.response.v1` for provider responses. That schema includes doctest-specific classification labels, while doctest-specific evidence belongs in the doctest AI context packet rather than a separate explain response schema.

## Forbidden AI Behavior

AI must not:

- decide doctest pass/fail status
- update documentation examples automatically
- approve snapshot changes
- mark doctest mutants equivalent
- suppress failing doctests
- execute commands
- decide mutation correctness

## AI Context Shape

Doctest AI context extends the existing advisory pattern. `zentinel.ai.doctest.context.v1` is introduced by task `055` for the non-survivor flows `explain_doctest_failure`, `suggest_doctest`, `review_snapshot`, and `suggest_missing_doctests`. Task `067` later extends the same v1 schema with the deferred `explain_doctest_survivor` branch after task `061` defines stable mutation-aware doctest report fields. The schema file must not accept schema-version-only placeholders.

```json
{
  "schema_version": "zentinel.ai.doctest.context.v1",
  "flow": "explain_doctest_failure",
  "created_by": "zentinel",
  "provider_mode": "stub",
  "project": {
    "name": "example",
    "root_label": "<project>",
    "zig_version": "0.16.0",
    "zentinel_version": "0.1.0"
  },
  "doctest": {
    "id": "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
    "file": "docs/CLI_SPEC.md",
    "line_start": 47,
    "line_end": 54,
    "source_ref": "docs/CLI_SPEC.md:47:help-output",
    "block_refs": ["docs/CLI_SPEC.md:47:help-output", "docs/CLI_SPEC.md:54:help-output"],
    "kind": "cli",
    "status": "failed"
  },
  "evidence": {
    "kind": "case_failure",
    "command": {
      "original": "zentinel --help",
      "argv": ["zentinel", "--help"],
      "cwd": "<project>",
      "environment_policy": "minimal",
      "shell": false
    },
    "status": "failed",
    "expected_excerpt": "Usage:",
    "actual_excerpt": "USAGE:",
    "normalized_expected_excerpt": "Usage:",
    "normalized_actual_excerpt": "USAGE:",
    "diagnostics": [],
    "failure_summary": "stdout did not contain expected text"
  },
  "privacy": {
    "remote_allowed": false,
    "source_context_policy": "minimal",
    "redactions_applied": []
  }
}
```

Required top-level fields:

| Field | Rule |
| --- | --- |
| `schema_version` | Constant `zentinel.ai.doctest.context.v1`. |
| `flow` | For task `055`, one of `explain_doctest_failure`, `suggest_doctest`, `review_snapshot`, or `suggest_missing_doctests`. Task `067` adds `explain_doctest_survivor`; task `055` must reject that flow. |
| `created_by` | Constant `zentinel`. |
| `provider_mode` | `disabled`, `stub`, `local`, or `remote`. |
| `project` | Same privacy-filtered project summary shape as mutation AI context. |
| `doctest` | Selected case metadata or docs-target metadata, depending on flow. |
| `evidence` | Bounded deterministic evidence for the selected flow. |
| `privacy` | Redaction and remote-provider policy metadata. |

`doctest` fields for case-based flows:

| Field | Rule |
| --- | --- |
| `id` | Durable `dt_...` case ID from the selected report or extraction. Required for case-based flows. |
| `file` | Project-relative docs path. |
| `line_start`, `line_end` | Display-only line evidence, both one-based integers. |
| `source_ref` | Anchor-line source ref, never a secondary expectation block. |
| `block_refs` | Secondary block refs retained for diagnostics and display. |
| `kind` | Exact doctest report case kind: `zig_compile_pass`, `zig_test`, `zig_compile_fail`, `cli`, `config`, `config_fail`, or `mutation`. Expectation-only blocks do not appear as doctest `kind` values. |
| `status` | Deterministic status from the report or extraction. |

For `explain_doctest_survivor`, the top-level `doctest` object is the selected mutation-aware report case and must have `kind = "mutation"` and `status = "survived"`. Metadata for the original preflight doctest case lives in `evidence.source_case`; agents must not overload one `case` object to mean both the original passing doctest and the survived mutation entry.

`doctest` fields for docs-target flows such as `suggest_doctest` and `suggest_missing_doctests`:

| Field | Rule |
| --- | --- |
| `id` | `null`, because there is no selected case yet. |
| `file` | Existing project-relative docs path. |
| `line_start`, `line_end` | One-based insertion range when known, otherwise `null`. |
| `source_ref` | `null`, because source refs select existing cases only. |
| `block_refs` | Empty array unless optional report context identifies nearby cases. |
| `kind` | Constant `docs_target`. |
| `status` | Constant `not_applicable`. |

`evidence` variants use an exact `kind` discriminant. Task `055` owns the first four variants. Task `067` owns the deferred `doctest_survivor` variant and must add it only after task `061` stabilizes mutation-aware report fields.

| Flow | Evidence `kind` | Evidence required |
| --- | --- | --- |
| `explain_doctest_failure` | `case_failure` | Structured command evidence when available, normalized expected/actual excerpts, diagnostics, and deterministic status. |
| `suggest_doctest` | `docs_target` | `target_file`, `heading_context`, `docs_metadata`, and nullable `report_summary`. |
| `review_snapshot` | `snapshot_diff` | `snapshot` copied from `case.result.snapshot`, selected `case_status`, and no AI-computed match result. |
| `suggest_missing_doctests` | `missing_doctests` | Deterministic public-docs metadata and `candidates` with `file`, `heading`, `reason`, and `missing_kind`. |
| `explain_doctest_survivor` | `doctest_survivor` | `survivor_ref`, `source_case`, selected `mutation_case`, `mutated_diff`, `operator`, and deterministic runner evidence from the mutation-aware doctest report. |

Closed evidence object rules:

| Evidence `kind` | Required fields | Nullable or optional fields |
| --- | --- | --- |
| `case_failure` | `kind`, `status`, `command`, `expected_excerpt`, `actual_excerpt`, `normalized_expected_excerpt`, `normalized_actual_excerpt`, `diagnostics`, `failure_summary` | `command`, `expected_excerpt`, `actual_excerpt`, `normalized_expected_excerpt`, and `normalized_actual_excerpt` may be `null` only when the selected case did not produce that evidence. |
| `docs_target` | `kind`, `target_file`, `heading_context`, `docs_metadata`, `report_summary` | `report_summary` is `null` when no report context is supplied. |
| `snapshot_diff` | `kind`, `case_status`, `snapshot` | None. `snapshot` is copied exactly from `case.result.snapshot`. |
| `missing_doctests` | `kind`, `docs`, `candidates` | `candidate.line_hint` may be `null`. |
| `doctest_survivor` | `kind`, `survivor_ref`, `source_case`, `mutation_case`, `mutant_id`, `mutated_diff`, `operator`, `operator_stability`, `backend`, `backend_stability`, `runner_evidence` | Deferred to task `067`; not accepted by the task `055` schema. |

`docs_metadata` is a closed object with:

| Field | Rule |
| --- | --- |
| `public` | Boolean saying whether the docs path is in the public-docs set. |
| `has_doctests` | Boolean from deterministic extraction metadata. |
| `executable_case_count` | Non-negative integer count of executable doctest cases in the target file. |
| `nearest_heading` | String heading nearest to the target insertion point, or `null`. |

`report_summary`, when non-null, is a closed object with the ordinary doctest status count keys `total`, `passed`, `failed`, `compile_error`, `expected_compile_error`, `timeout`, `skipped`, and `invalid`.

`diagnostics` entries are closed objects with required `code` and `message` fields plus nullable `file`, `line`, and `column` fields. Paths are project-relative and line/column values are one-based integers when present.

`missing_doctests.docs` entries are closed objects with `file`, `public`, `has_doctests`, and `executable_case_count`. `missing_doctests.candidates` entries are closed objects with `file`, `heading`, `line_hint`, `reason`, and `missing_kind`, where `missing_kind` is one of `cli`, `config`, `report`, `mutation`, or `zig_test`.

The deferred `doctest_survivor.source_case` and `doctest_survivor.mutation_case` objects both reuse the closed case-based doctest metadata shape above: `id`, `file`, `line_start`, `line_end`, `source_ref`, `block_refs`, `kind`, and `status`. `source_case` describes the original ordinary doctest case referenced by `case.mutation.doctest_case_id`; it must not use `kind = "mutation"`. `mutation_case` describes the selected mutation-aware report entry; it must use `kind = "mutation"` and `status = "survived"`. The deferred `doctest_survivor.runner_evidence` object is copied from `case.mutation.runner_evidence` in the selected mutation-aware doctest report. It is closed and contains `status`, `command`, `exit_code`, `timed_out`, `stdout_excerpt`, `stderr_excerpt`, `failure_summary`, and `skip_reason`. Examples use illustrative line numbers; executable fixtures must derive source refs from current extraction metadata rather than copying example line numbers.

Minimal evidence examples:

```json
{ "kind": "case_failure", "status": "failed", "command": { "original": "zentinel --help", "argv": ["zentinel", "--help"], "cwd": "<project>", "environment_policy": "minimal", "shell": false }, "expected_excerpt": "Usage:", "actual_excerpt": "USAGE:", "normalized_expected_excerpt": "Usage:", "normalized_actual_excerpt": "USAGE:", "diagnostics": [], "failure_summary": "stdout did not contain expected text" }
```

```json
{ "kind": "docs_target", "target_file": "docs/CLI_SPEC.md", "heading_context": ["AI Commands"], "docs_metadata": { "public": true, "has_doctests": true, "executable_case_count": 3, "nearest_heading": "AI Commands" }, "report_summary": null }
```

```json
{ "kind": "snapshot_diff", "case_status": "failed", "snapshot": { "expected_excerpt": "Usage:", "actual_excerpt": "USAGE:", "normalized_expected_excerpt": "Usage:", "normalized_actual_excerpt": "USAGE:", "match_mode": "contains", "expected_block_ref": "docs/CLI_SPEC.md:54:help-output", "actual_ref": "stdout", "matched": false } }
```

```json
{ "kind": "missing_doctests", "docs": [{ "file": "docs/CONFIG_SPEC.md", "public": true, "has_doctests": false, "executable_case_count": 0 }], "candidates": [{ "file": "docs/CONFIG_SPEC.md", "heading": "Minimal Config", "line_hint": 19, "reason": "Public config contract lacks an executable block.", "missing_kind": "config" }] }
```

```json
{ "kind": "doctest_survivor", "survivor_ref": "ds_01hr7p6h0v2fj3drdzt9k2a0xe", "source_case": { "id": "dt_01hr7p6h0v2fj3drdzt9k2a0xe", "file": "docs/MUTATOR_SPEC.md", "line_start": 120, "line_end": 132, "source_ref": "docs/MUTATOR_SPEC.md:120:range-boundary", "block_refs": ["docs/MUTATOR_SPEC.md:120:range-boundary"], "kind": "zig_test", "status": "passed" }, "mutation_case": { "id": "dm_01hr7p6h0v2fj3drdzt9k2a0xe", "file": "docs/MUTATOR_SPEC.md", "line_start": 120, "line_end": 132, "source_ref": "docs/MUTATOR_SPEC.md:120:range-boundary", "block_refs": ["docs/MUTATOR_SPEC.md:120:range-boundary"], "kind": "mutation", "status": "survived" }, "mutant_id": "m_01hr7p6h0v2fj3drdzt9k2a0xe", "mutated_diff": ["- try expect(idx < len);", "+ try expect(idx <= len);"], "operator": "comparison_boundary", "operator_stability": "stable", "backend": "ast", "backend_stability": "stable", "runner_evidence": { "status": "survived", "command": { "original": "zig test src/doctest.zig", "argv": ["zig", "test", "src/doctest.zig"], "cwd": "<project>", "environment_policy": "minimal", "shell": false }, "exit_code": 0, "timed_out": false, "stdout_excerpt": "", "stderr_excerpt": "", "failure_summary": "", "skip_reason": null } }
```

The schema must set `additionalProperties: false` for top-level objects and nested objects unless a nested object is explicitly documented as an open map. The context must contain only:

- selected doctest blocks
- normalized output excerpts
- deterministic status
- relevant docs path and line numbers
- privacy metadata

It must not contain:

- full documentation files by default
- unbounded command output
- user home directory paths
- source refs as canonical IDs when a durable `dt_...` ID exists
- AI-generated classifications as deterministic evidence

## AI-Generated Example Suggestions

AI may suggest blocks in supported formats.

Example advisory output:

````json
{
  "schema_version": "zentinel.ai.doctest.suggest.response.v1",
  "suggestions": [
    {
      "target_file": "docs/CONFIG_SPEC.md",
      "line_hint": 19,
      "reason": "The minimal config example should be executable.",
      "block": "```toml config\n[project]\nname = \"example\"\n\n[test]\ncommands = [\"zig build test\"]\n```"
    }
  ]
}
````

Response schema target:

| Field | Rule |
| --- | --- |
| `schema_version` | Constant `zentinel.ai.doctest.suggest.response.v1`. |
| `suggestions` | Array with `minItems: 1` and `maxItems: 3`. |

Each suggestion requires:

| Field | Rule |
| --- | --- |
| `target_file` | Existing project-relative documentation path for `zentinel doctest suggest <doc-path>`. |
| `line_hint` | One-based integer or `null` when no stable insertion point exists. |
| `reason` | Non-empty advisory rationale. |
| `block` | One complete doctest block in a supported format from `docs/DOCTEST_BLOCK_FORMATS.md`. |

The response schema must use `additionalProperties: false`. It must reject absolute paths, paths outside the project, full-document rewrites, more than three suggestions, and fields that attempt to set doctest status.

Agents may use suggestions as drafts, but tests and human-readable docs remain repository-owned artifacts. Doctest AI suggestions are returned as advisory CLI output and are not persisted by default. If a future task adds persistence, it must use an advisory-only artifact or `advisory.ai`, never deterministic doctest result fields.

## Snapshot Review

AI may compare normalized expected and actual output:

```json
{
  "schema_version": "zentinel.ai.doctest.snapshot_review.response.v1",
  "classification": "wording_change",
  "summary": "The help heading changed from 'Usage' to 'USAGE'.",
  "risk": "medium",
  "evidence_refs": [
    {
      "kind": "block_ref",
      "ref": "docs/CLI_SPEC.md:54:help-output"
    }
  ],
  "next_action": "Review the public CLI wording before updating the expected output block."
}
```

Response schema target:

| Field | Rule |
| --- | --- |
| `schema_version` | Constant `zentinel.ai.doctest.snapshot_review.response.v1`. |
| `classification` | One of `wording_change`, `formatting_change`, `normalization_change`, `semantic_change`, `unclear`. |
| `summary` | Non-empty advisory summary grounded in provided expected/actual evidence. |
| `risk` | One of `low`, `medium`, `high`, `unclear`. |
| `evidence_refs` | Array of `{ "kind": string, "ref": string }` objects pointing only to provided case, block, or report refs. |
| `next_action` | Non-empty advisory recommendation. |

The schema must use `additionalProperties: false` and reject any field that approves, applies, or suppresses a snapshot update.

AI must not update snapshots itself.

## Missing Doctest Suggestions

AI may scan deterministic docs metadata and suggest missing doctests:

- public CLI commands without `bash cli`
- config examples not tagged `toml config`
- report examples not tagged `json expected`
- mutator transformations not expressed as `zig before`/`zig after`

The actual missing-doctest list must be validated by deterministic extraction where possible.

## Doctest Survivor Explanation

For `doctest --mutate`, AI may explain:

- which documentation example survived mutation
- what behavioral assertion appears weak
- which edge case might be missing

Example:

```text
The doctest checks idx < len but does not check idx == len. Add an executable example that expects error.OutOfBounds when idx equals len.
```

This is advisory. The survivor status is determined only by running the mutated doctest.

## Privacy

Doctest AI follows `docs/AI_ASSISTED_UX.md` privacy rules.

Additional doctest rules:

- do not send entire documentation files by default
- send only the failing case and nearby heading context
- redact command output before prompt construction
- never send generated temp workspace paths without normalization
