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
| Report JSON example | `json expected` | JSON must satisfy schema or match produced output. |
| Text output example | `text output` | Output snapshot for preceding executable block. |
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

Source refs have the form `docs/path.md:line[:label]`. The `line` component resolves only against the case anchor line. They are accepted by CLI selectors such as `--case <case-ref>` and `doctest explain <case-ref>` when they resolve to exactly one case in the current extraction or selected doctest report. A line pointing only to a secondary expectation block must fail with a case-ref diagnostic instead of guessing the producer case. Reports must store durable `id` values, the anchor `source_ref`, and may also store secondary `block_refs`, source location fields, and labels for display.

## Doctest Reports

Minimal JSON shape:

```json
{
  "schema_version": "zentinel.doctest.report.v1",
  "summary": {
    "total": 1,
    "passed": 1,
    "failed": 0
  },
  "cases": [
    {
      "id": "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
      "file": "docs/CLI_SPEC.md",
      "line_start": 47,
      "source_ref": "docs/CLI_SPEC.md:47:help-output",
      "block_refs": ["docs/CLI_SPEC.md:47:help-output", "docs/CLI_SPEC.md:54:help-output"],
      "kind": "cli",
      "status": "passed"
    }
  ]
}
```

The report schema should be added before implementation reaches doctest reporting.

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
