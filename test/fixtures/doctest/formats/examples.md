# Doctest Fixture Examples

Representative fenced blocks for every supported doctest format defined in
`docs/DOCTEST_BLOCK_FORMATS.md`. These are deterministic, short fixture inputs
for the future doctest parser/extraction work (tasks 031+); no doctest execution
code exists yet. The info string grammar is
`<language> [kind] [match-mode] [case:<label>] [key:value ...]`.

## zig test

```zig test
const std = @import("std");

test "add is commutative for a tiny case" {
    try std.testing.expect(1 + 2 == 2 + 1);
}
```

## zig compile_fail

```zig compile_fail
pub fn bad() void {
    // Returning a value from a void function must not compile.
    return 1;
}
```

## bash cli

```bash cli case:help
zentinel --help
```

## text output

```text output contains
zentinel - Zig-native mutation testing
```

## json expected

```json expected subset
{
  "schema_version": "zentinel.report.v1"
}
```

## toml config

```toml config
[project]
name = "example"
include = ["src/**/*.zig"]
```

## zig before / zig after

A mutator example expressed as paired before/after compile-pass snippets.

```zig before
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```zig after
pub fn add(a: i32, b: i32) i32 {
    return a - b;
}
```

## Future doctest properties (documented, not yet executable)

Later parser/extraction tasks (031+) must preserve these deterministic
properties; they are recorded here so fixture targets are stable:

- **Extraction order**: cases are sorted by file path, then 1-based block line
  start, then block index within the file.
- **Case ID stability**: a case's deterministic ID is a function of its file
  path, anchor line, language/kind tags, and content, so unrelated edits
  elsewhere in the document do not renumber or re-key existing cases.
- **Block classification determinism**: a fence's info string maps to exactly
  one block kind by the grammar above; unknown tags are invalid (never silently
  reclassified), and a plain `zig` block never consumes a `text output` block.
