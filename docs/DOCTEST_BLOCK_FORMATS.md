# Doctest Block Formats

This document defines every supported doctest fenced block format. Agents must use these formats for executable documentation.

## Info String Grammar

```text
<language> [kind] [match-mode] [case:<label>] [zero-or-more key:value metadata entries]
```

Examples:

```text
zig test
zig compile_fail
json expected subset
text output contains
bash cli case:help
toml config
```

Unknown tags are invalid unless a future task updates this document.

## Common Extraction Rules

- fenced blocks must use backticks
- Supported doctest fences use exactly three or four backticks.
- opening and closing doctest fences must use the same supported length
- longer backtick fences are documentation-only until a future task explicitly extends parser support
- content is preserved exactly before normalization
- block line numbers are 1-based
- cases are sorted by file path, line start, and block index

## `zig`

````md
```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```
````

Semantics:

- compile-pass snippet
- no test assertions required
- fails if compiler rejects the generated file

Execution:

- write to `src/doctest.zig`
- compile with deterministic Zig command

Matching:

- success is exit code `0`

## `zig test`

````md
```zig test
const std = @import("std");

test "example" {
    try std.testing.expect(true);
}
```
````

Semantics:

- executable Zig test snippet
- must pass under `zig test`

Execution:

```bash
zig test src/doctest.zig
```

Matching:

- success is exit code `0`
- output may be matched by following `text output`

## `zig compile_fail`

````md
```zig compile_fail
pub fn broken() void {
    return 1;
}
```
````

Semantics:

- snippet must fail compilation

Execution:

- compile with the same wrapper as `zig`
- require non-zero compiler exit

Matching:

- any compile failure passes if no expected block follows
- following `text output` or `diagnostic expected` may constrain diagnostics

## `zig before`

````md
```zig before
if (idx >= len) return error.OutOfBounds;
```
````

Semantics:

- source before mutation
- used by mutator spec and future `doctest --mutate`

Execution:

- no normal execution by itself
- must pair with `zig after`

Matching:

- future mutation-aware mode verifies documented transformation exists

## `zig after`

````md
```zig after
if (idx > len) return error.OutOfBounds;
```
````

Semantics:

- expected source after mutation
- must follow a matching `zig before`

Matching:

- exact normalized source comparison for mutation output

## `json expected`

````md
```json expected
{
  "schema_version": "zentinel.report.v1"
}
```
````

Semantics:

- expected JSON output from preceding executable block

Execution:

- no direct execution
- parses as JSON during doctest planning

Matching:

- exact semantic JSON by default
- `subset` allows expected object to be a subset
- arrays remain order-sensitive unless tagged `unordered`

Normalization:

- key order ignored
- whitespace ignored
- numbers compare as JSON numbers

## `text output`

````md
```text output
created zentinel.toml
```
````

Semantics:

- expected stdout/stderr output from preceding executable block

Matching modes:

| Tag | Rule |
| --- | --- |
| none | exact normalized text match |
| `contains` | expected lines appear in order |
| `regex` | expected content is a regular expression |

Default is exact.

Normalization:

- line endings to `\n`
- trim trailing whitespace on lines only when tagged `trim`
- replace absolute project root with `<project>`
- replace temp directories with `<tmp>`
- remove ANSI color when command uses `--no-color`

## `diagnostic expected`

````md
```diagnostic expected
error[ZNTL_CONFIG_UNKNOWN_KEY]: unsupported config key
```
````

Semantics:

- expected compiler-like diagnostic
- primarily for compile-fail and config-fail cases

Matching:

- normalized path and line comparison
- exact error code comparison when present

## `bash cli`

````md
```bash cli
zentinel version
```
````

Semantics:

- zentinel CLI example

Execution:

- run through doctest CLI executor
- command must start with `zentinel`
- shell metacharacters are invalid by default

Matching:

- following `text output`, `json expected`, or exit-code metadata

Allowed metadata:

```text
exit:0
exit:2
cwd:fixture
```

## `toml config`

````md
```toml config
[project]
name = "example"

[test]
commands = ["zig build test"]
```
````

Semantics:

- valid zentinel config example

Execution:

- parse and validate through config module

Matching:

- pass when valid
- optional following `json expected` may match normalized config representation

## `toml config_fail`

````md
```toml config_fail
[backend]
default = "zir"
```
````

Semantics:

- invalid config example

Execution:

- parse and validate
- require diagnostic failure

Matching:

- following `text output contains` or `diagnostic expected` should match error

## Unsupported Blocks

The following are documentation-only unless explicitly tagged with a supported doctest kind:

```text
text
json
bash
diff
mermaid
```

Rationale:

- ordinary docs should remain readable
- executable behavior must be explicit
- no agent should infer execution from prose

## Normalization Rules

All doctest matching applies:

- path separators normalized to `/`
- project root replaced with `<project>`
- temporary directories replaced with `<tmp>`
- duration values replaced with `<duration>`
- run IDs replaced with `<run-id>`
- mutant IDs replaced with `<mutant-id>` when examples do not test identity
- ANSI color stripped unless color is the explicit subject
