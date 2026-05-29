# Doctest Specification

Doctests are executable documentation cases extracted from Markdown fenced code blocks. They verify that documented examples compile, run, fail, or match expected output exactly as specified.

## Command Surface

Planned commands:

```bash
zentinel doctest
zentinel doctest --mutate
zentinel doctest --format json
zentinel doctest --file docs/CLI_SPEC.md
zentinel doctest --case dt_01hr7p6h0v2fj3drdzt9k2a0xe
zentinel doctest --case docs/CLI_SPEC.md:47:help-output
zentinel doctest explain-survivor ds_01hr7p6h0v2fj3drdzt9k2a0xe
```

`zentinel doctest` validates documentation examples.

`zentinel doctest --mutate` first validates examples normally, then uses mutation testing to check whether the examples are behaviorally strong enough to detect documented mutations.

## Supported Case Types

| Case type | Blocks | Purpose |
| --- | --- | --- |
| Zig compile-pass | `zig` | Code snippet must compile when wrapped if needed. |
| Zig test | `zig test` | Snippet must pass under `zig test`. |
| Zig compile-fail | `zig compile_fail` plus optional expected output | Snippet must fail compilation deterministically. |
| CLI example | `bash cli` plus `text output` or `json expected` | zentinel command example must match output. |
| Config example | `toml config` | Config must parse and validate. |
| Config failure example | `toml config_fail` plus optional expected output | Config must fail validation deterministically. |
| Expectation block | `text output`, `json expected`, or `diagnostic expected` | Secondary matching block attached to the preceding producer case. |
| Mutation example | `zig before` plus `zig after` | Future mutation-aware documentation validation. |

## General Execution Semantics

Every doctest case has:

- stable durable case ID
- optional source ref selector
- source documentation path
- line range
- block type
- execution plan
- expected result
- normalization mode
- deterministic status

Allowed statuses:

```text
passed
failed
compile_error
expected_compile_error
timeout
skipped
invalid
```

`expected_compile_error` is a pass status for `zig compile_fail` only.

Any ordinary doctest status other than `passed`, `skipped`, or `expected_compile_error` makes `zentinel doctest` exit `1`. Invalid CLI/config/case selector usage still exits `2`, and internal zentinel failures exit `4`.

## Doctest Case Kind Enum

`case.kind` in `zentinel.doctest.report.v1` must be one of exactly:

```text
zig_compile_pass
zig_test
zig_compile_fail
cli
config
config_fail
mutation
```

Expectation-only blocks do not produce standalone `case.kind` values. Blocks such as `text output`, `json expected`, `diagnostic expected`, and `zig after` are stored as expectation, snapshot, diagnostic, or secondary block evidence on the producer case.

`docs_target` is an AI-only kind used by `zentinel.ai.doctest.context.v1` for suggestion flows. It must never appear as a `zentinel.doctest.report.v1` case kind.

## Zig Compile-Pass Blocks

Plain Zig blocks are compile-pass examples unless tagged otherwise.

Example:

````md
```zig
const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```
````

Execution:

1. Write snippet into generated `src/doctest.zig`.
2. If snippet has no tests, compile it with `zig build-exe` or `zig test` depending on wrapper policy.
3. Require successful compilation.

Wrapping rule:

- snippets containing top-level declarations are written as-is
- expression-only snippets require an explicit future `zig expr` block and are not inferred

## Zig Test Blocks

Use `zig test` for snippets with executable assertions.

Example:

````md
```zig test
const std = @import("std");

fn isBoundary(idx: usize, len: usize) bool {
    return idx >= len;
}

test "detects upper boundary" {
    try std.testing.expect(isBoundary(4, 4));
}
```
````

Execution:

```bash
zig test src/doctest.zig
```

Expected result:

- exit code `0`
- no timeout

## Compile-Fail Blocks

Use `zig compile_fail` when docs intentionally show invalid code.

Example:

````md
```zig compile_fail
pub fn broken() void {
    return 1;
}
```

```text output contains
expected type 'void'
```
````

Execution:

- compile the snippet
- require non-zero compiler exit
- normalize diagnostics
- match optional expected output

If no expected output block is present, any compiler failure passes. Specs should prefer expected diagnostic snippets for public docs.

## CLI Example Tests

Use `bash cli` for zentinel command examples.

Example:

````md
```bash cli
zentinel --help
```

```text output
zentinel - Zig-native mutation testing

Usage:
  zentinel <command> [options]
```
````

Rules:

- command must begin with `zentinel`
- no shell pipes by default
- no network commands
- output is normalized before matching
- examples run in a generated workspace unless marked read-only

## JSON Output Tests

Use `json expected` to match JSON output from a previous CLI block or report-producing doctest.

Example:

````md
```bash cli
zentinel run --config test/fixtures/arithmetic/zentinel.toml --report json
```

```json expected subset
{
  "schema_version": "zentinel.report.v1",
  "summary": {
    "survived": 1
  }
}
```
````

Matching:

- parse actual and expected JSON
- expected JSON may be a subset only when tagged `subset`
- object key order is ignored
- arrays are order-sensitive unless tagged `unordered`
- schema version must match exactly

## Config Example Tests

Use `toml config` for config snippets.

Example:

````md
```toml config
[project]
name = "example"

[test]
commands = ["zig build test"]
```
````

Execution:

- write snippet to generated `zentinel.toml`
- parse through zentinel config parser
- validate defaults
- require no validation errors

Invalid config examples use:

````md
```toml config_fail
[backend]
default = "zir"
```

```text output contains
experimental backend
```
````

## Snapshot Tests

Snapshot blocks use `text output`, `json expected`, or `diagnostic expected`.

Snapshot normalization is defined in `docs/DOCTEST_ARCHITECTURE.md`.

Snapshot updates are never automatic in default doctest runs. Agents must review semantic diffs before updating expected blocks.

## Case Labels

Blocks may include labels:

````md
```zig test case:boundary-check
```
````

Rules:

- labels are project-local identifiers
- labels must match `^[a-z0-9][a-z0-9_-]*$`
- duplicate labels in one file are invalid
- labels appear in reports

## Case Identity

Durable doctest case IDs use the `dt_` prefix and are derived from project-relative documentation path, case kind, explicit label when present, normalized block grouping metadata, and a content hash of the grouped blocks. Line numbers are evidence and source-ref selectors, not durable ID inputs, so adding unrelated prose outside the case must not change the durable ID.

Duplicate unlabeled cases in the same file are invalid when they have the same case kind, normalized grouping metadata, and grouped-block content hash. The extractor must report them as ambiguous instead of adding line numbers or occurrence indexes to the durable ID. Authors should add explicit case labels when two examples are intentionally identical.

Each case has a canonical anchor line. The anchor line is the first executable or producer block in the group: `zig test`, `zig compile_fail`, `bash cli`, `toml config`, `toml config_fail`, `zig before`, or the producer block paired with `text output` or `json expected`. Expectation-only blocks such as `text output`, `json expected`, and `zig after` are secondary block refs, not source-ref anchors.

Source refs have the form `docs/path.md:line[:label]`. The `line` component resolves only against the case anchor line. They are accepted by CLI selectors such as `--case <case-ref>` and `doctest explain <case-ref>` when they resolve to exactly one case in the current extraction or selected doctest report. Examples in this file use illustrative line numbers; executable fixtures must derive source refs from current extraction metadata rather than copying example line numbers. A line pointing only to a secondary expectation block must fail with a case-ref diagnostic instead of guessing the producer case. Reports must store durable `id` values, the anchor `source_ref`, and may also store secondary `block_refs`, source location fields, and labels for display.

### Doctest Mutation Entry IDs

Mutation-aware doctest entry IDs use the `dm_...` prefix. They are durable IDs for individual `case.kind = "mutation"` report entries across killed, survived, skipped, invalid, compile-error, compiler-crash, and timeout outcomes.

For mutation-aware entries, `case.id` is a durable `dm_...` ID. The original ordinary doctest case remains available as `case.mutation.doctest_case_id = "dt_..."`. Mutation-aware entries must not reuse the ordinary `dt_...` value in `case.id`, because one ordinary doctest case may produce multiple documentation mutants and non-survived entries have `case.mutation.survivor_ref = null`.

The deterministic derivation is:

```text
dm_ + first_26_chars(lowercase_unpadded_crockford_base32(sha256(canonical_mutation_case_bytes)))
```

`canonical_mutation_case_bytes` is UTF-8 text with `\n` separators and this exact field order:

```text
zentinel.doctest_mutation_case.v1
doctest_case_id
mutant_id
operator
doc_file
source_ref
normalized_mutated_diff
```

The derivation must not include display order, wall-clock time, absolute paths, command output, result duration, result status, or AI output. `normalized_mutated_diff` uses the same normalization rules as survivor refs. A mutation-aware doctest report must not contain duplicate `dm_...` case IDs.

### Doctest Survivor Refs

Mutation-aware doctest survivor refs use the `ds_` prefix. They are durable selectors for survived documentation mutants inside a selected `zentinel doctest --mutate` report and are consumed by `zentinel doctest explain-survivor <survivor-ref>`.

`survivor_ref` is emitted only when `case.kind = "mutation"` and `case.status = "survived"`. Killed, skipped, invalid, compile-error, compiler-crash, and timeout documentation mutants set `survivor_ref` to `null` and are not valid `explain-survivor` targets.

The deterministic derivation is:

```text
ds_ + first_26_chars(lowercase_unpadded_crockford_base32(sha256(canonical_survivor_bytes)))
```

`canonical_survivor_bytes` is UTF-8 text with `\n` separators and this exact field order:

```text
zentinel.doctest_survivor.v1
doctest_case_id
mutant_id
operator
doc_file
source_ref
normalized_mutated_diff
```

The derivation must not include display order, wall-clock time, absolute paths, command output, result duration, or AI output. `normalized_mutated_diff` uses project-relative paths and `/` separators, with trailing whitespace stripped from each diff line before hashing. A mutation-aware doctest report must not contain duplicate non-null `survivor_ref` values.

## Doctest Reports

`zentinel.doctest.report.v1` is the exact schema target for task `035`. JSON doctest reports must be deterministic, use project-relative paths, and normalize observation metadata in snapshots.

Minimal valid JSON shape:

```json
{
  "schema_version": "zentinel.doctest.report.v1",
  "run": {
    "id": "doctest_run_01hr7pc9qdyj2f3d7z7me3x1rk",
    "status": "completed",
    "zentinel_version": "0.1.0",
    "zig_version": "0.16.0",
    "command": "zentinel doctest --file docs/CLI_SPEC.md --format json",
    "project_root": "<project>",
    "started_at": "<normalized>",
    "duration_ms": 0
  },
  "summary": {
    "total": 1,
    "passed": 1,
    "failed": 0,
    "compile_error": 0,
    "expected_compile_error": 0,
    "timeout": 0,
    "skipped": 0,
    "invalid": 0
  },
  "cases": [
    {
      "id": "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
      "file": "docs/CLI_SPEC.md",
      "line_start": 47,
      "line_end": 54,
      "source_ref": "docs/CLI_SPEC.md:47:help-output",
      "block_refs": ["docs/CLI_SPEC.md:47:help-output", "docs/CLI_SPEC.md:54:help-output"],
      "kind": "cli",
      "status": "passed",
      "expectation": {
        "mode": "contains",
        "block_ref": "docs/CLI_SPEC.md:54:help-output"
      },
      "command": {
        "original": "zentinel --help",
        "argv": ["zentinel", "--help"],
        "cwd": "<project>",
        "environment_policy": "minimal",
        "shell": false
      },
	      "result": {
	        "exit_code": 0,
	        "timed_out": false,
	        "duration_ms": 0,
	        "stdout_excerpt": "zentinel - Zig-native mutation testing",
	        "stderr_excerpt": "",
	        "normalized_stdout_excerpt": "zentinel - Zig-native mutation testing",
	        "normalized_stderr_excerpt": "",
	        "snapshot": {
	          "expected_excerpt": "zentinel - Zig-native mutation testing",
	          "actual_excerpt": "zentinel - Zig-native mutation testing",
	          "normalized_expected_excerpt": "zentinel - Zig-native mutation testing",
	          "normalized_actual_excerpt": "zentinel - Zig-native mutation testing",
	          "match_mode": "contains",
	          "expected_block_ref": "docs/CLI_SPEC.md:54:help-output",
	          "actual_ref": "stdout",
	          "matched": true
	        },
	        "failure_summary": ""
	      },
      "diagnostics": [],
      "advisory": {
        "ai": null
      }
    }
  ]
}
```

Report field rules:

| Field | Rule |
| --- | --- |
| `schema_version` | Constant `zentinel.doctest.report.v1`. |
| `run.status` | `completed`, `failed`, or `internal_error`. |
| `run.error` | `run.error` is required and null for `completed` or `failed`; for `internal_error` it is a closed object with required `code`, `message`, and `phase`, optional bounded `details`, and no AI-generated explanation. |
| `summary` | For normal `zentinel doctest`, counts only non-mutation entries in `cases` and includes every ordinary doctest status key; `total` equals the sum of ordinary status-count fields. For `zentinel doctest --mutate`, this same top-level summary still counts only preflight non-mutation doctest entries, while mutation entries are counted only in `summary.mutation`. |
| `cases` | Sorted by project-relative file path, anchor line, block index, and durable case ID. |
| `case.id` | Durable `dt_...` ID for ordinary non-mutation cases; durable `dm_...` ID for mutation-aware entries where `case.kind = "mutation"`. |
| `case.source_ref` | Anchor-line source ref for selectors. |
| `case.block_refs` | All grouped block refs, including secondary expectation blocks. |
| `case.kind` | One of the exact values from the Doctest Case Kind Enum. |
| `case.status` | One of the allowed statuses listed above. |
| `case.command` | Structured command evidence when the case executes a command, otherwise `null`. |
| `case.result` | Bounded deterministic execution, normalization, and mismatch evidence when available. |
| `case.result.snapshot` | Required when output matching or snapshot evidence exists; otherwise `null`. Non-null snapshot objects require `expected_excerpt`, `actual_excerpt`, `normalized_expected_excerpt`, `normalized_actual_excerpt`, `match_mode`, `expected_block_ref`, `actual_ref`, and `matched`. |
| `case.diagnostics` | Array of compiler-like diagnostics with stable error codes for invalid or failing cases. |
| `case.advisory.ai` | Optional advisory AI payload; never required for deterministic doctest execution. |

`additionalProperties` should be false for the report envelope, run object, summary object, case object, command object, result object, diagnostic object, and advisory object unless a future schema version explicitly opens a field.

Snapshot field rules:

| Field | Rule |
| --- | --- |
| `snapshot.expected_excerpt` | Bounded excerpt from the expected output block or diagnostic expectation. |
| `snapshot.actual_excerpt` | Bounded excerpt from the actual command output, compiler diagnostic, JSON output, or report field. |
| `snapshot.normalized_expected_excerpt` | Expected excerpt after doctest normalization. |
| `snapshot.normalized_actual_excerpt` | Actual excerpt after doctest normalization. |
| `snapshot.match_mode` | One of `exact`, `contains`, `regex`, `json`, `json_subset`, `json_unordered`, or `diagnostic`. |
| `snapshot.expected_block_ref` | Secondary block ref for the expected block, or `null` only when the expectation is implicit. |
| `snapshot.actual_ref` | One of `stdout`, `stderr`, `diagnostic`, `json`, or `report`. |
| `snapshot.matched` | Boolean result of deterministic matching. |

Failure report rules:

- Invalid blocks are emitted as `status = "invalid"` with a diagnostic using the documented doctest error code.
- Snapshot mismatches are emitted as `status = "failed"` with `case.result.snapshot.matched = false` plus expected, actual, and normalized excerpts in the snapshot object.
- Compile failures in `zig compile_fail` cases are `expected_compile_error` when they match the expected diagnostic and `compile_error` when they do not. `expected_compile_error` is counted under its own summary key and is successful for CLI exit behavior.
- Timeouts include `timed_out = true`, a `null` exit code, and bounded output excerpts.
- Doctest reports must not include AI-generated explanations unless the user invoked an AI command or a future task explicitly adds advisory report enrichment.

## Mutation-Aware Doctest Reports

Task `061` owns the stable `zentinel doctest --mutate` report extension. It must update `schemas/doctest.report.v1.schema.json` and report fixtures from the exact contract in this section before emitting mutation-aware reports outside the experimental fixture path.

Normal `zentinel doctest` reports use the ordinary doctest statuses listed above. Mutation-aware entries use `case.kind = "mutation"` and a shared mutation-result status:

```text
killed
survived
compile_error
compiler_crash
timeout
skipped
invalid
```

For `zentinel doctest --mutate`, `cases` may contain both ordinary preflight doctest entries and mutation entries. `summary` keeps the normal doctest status keys for the preflight doctest run and adds a `mutation` object at `summary.mutation` with these integer keys:

```text
total
killed
survived
compile_error
compiler_crash
timeout
skipped
invalid
```

`summary.total` equals the number of ordinary non-mutation doctest entries in `cases`. It must not include mutation entries. `summary.mutation.total` equals the number of entries where `case.kind = "mutation"`. It must not include preflight entries. The ordinary status-count fields and the mutation status-count fields are separate partitions; a case is counted in exactly one of them.

`case.mutation` is required and non-null when `case.kind = "mutation"`. It is absent or `null` for non-mutation doctest cases. The object is closed with `additionalProperties: false` and contains:

| Field | Rule |
| --- | --- |
| `mutant_id` | Durable `m_...` shared mutant ID for the documentation mutant. |
| `doctest_case_id` | Durable `dt_...` ID of the normal doctest case that was mutated. |
| `survivor_ref` | Durable `ds_...` survivor ref when `case.status = "survived"`; otherwise `null`. |
| `operator` | Stable mutator operator name from `docs/MUTATOR_SPEC.md`. |
| `operator_stability` | `stable`, `preview`, or `experimental`. |
| `backend` | `ast` for stable doctest mutation; `zir` and `air` remain experimental only. |
| `backend_stability` | `stable` or `experimental`. |
| `doc_file` | Project-relative documentation path that owns the doctest case. |
| `doc_line` | One-based anchor line for display and diagnostics only. |
| `source_ref` | Anchor-line source ref for the selected doctest case. |
| `mutated_diff` | Bounded array of normalized diff lines for the documentation mutant. |
| `runner_evidence` | Closed object copied from deterministic mutated-doctest command evidence. |

`case.mutation.runner_evidence` contains:

| Field | Rule |
| --- | --- |
| `status` | Same value as `case.status`. |
| `command` | Structured command evidence or `null` when the mutant was skipped before command execution. |
| `exit_code` | Integer process exit code or `null` for timeout/skipped/no process. |
| `timed_out` | Boolean timeout evidence. |
| `failure_kind` | Runner outcome class copied from deterministic command evidence: `none`, `compile_error`, `test_failure`, `compiler_crash`, `timeout`, or `skipped`. Survivor assistance reads this field instead of inferring the outcome class from prose. |
| `stdout_excerpt`, `stderr_excerpt`, `failure_summary` | Bounded normalized excerpts. |
| `skip_reason` | Stable skip reason string for skipped mutation entries; otherwise `null`. |

Mutation-aware case entries must not reuse the ordinary `dt_...` value in `case.id`. They must copy the ordinary case location fields (`file`, `source_ref`, `block_refs`, `line_start`, and `line_end`) and preserve the original ordinary case ID in `case.mutation.doctest_case_id` so selectors and AI evidence can join normal doctest results to documentation mutants without line-number-derived IDs.

## Invalid Doctests

Invalid doctests include:

- ambiguous expectation grouping
- duplicate unlabeled identical cases in the same file
- unsupported fence tags
- CLI blocks that do not start with `zentinel`
- JSON expected blocks without a producer
- mutation `before` without matching `after`
- nondeterministic examples without explicit normalization

Invalid doctests fail the doctest command.
