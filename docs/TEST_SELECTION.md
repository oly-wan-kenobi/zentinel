# Test Selection

Test selection controls which tests zentinel runs for each mutant. It is a performance optimization and a diagnostic aid, not a correctness shortcut.

## Goals

- run the smallest relevant test set when safe
- preserve deterministic behavior
- record why each test was selected
- allow full-suite fallback
- never hide a survivor from reports

## Strategies

| Strategy | Meaning |
| --- | --- |
| `all` | Run all configured test commands for every mutant. |
| `same_file` | Run tests associated with the mutated file. |
| `same_file_then_package` | Prefer same-file tests, fall back to package/build tests. |
| `impact_graph` | Use dependency/test impact analysis when available. |

Default:

```text
same_file_then_package
```

## Same-File Tests

Zig often colocates tests and implementation. For a mutation in `src/range.zig`, zentinel may select:

```bash
zig test src/range.zig
```

Generated same-file selected commands are authorized generated selected test commands, not arbitrary AI or shell output. A generated selected command must pass an unmutated preflight before it can classify a mutant. If the command was not part of the baseline command set, zentinel first runs it against the unmodified project, records that preflight evidence, and uses the command for mutant classification only if the preflight passes.

Same-file test bodies are not mutation targets by default.

## Build Tests

For projects that require `build.zig`, selection may run:

```bash
zig build test
```

When selection cannot prove a narrower command, it must fall back to configured full test commands.

## Impact Graph

Before task `051`, `impact_graph` is not available and must be rejected by config validation. Agents must not accept it as an alias for `same_file_then_package` or silently fall back to all tests.

The future impact graph may use:

- source imports
- package graph from build configuration
- historical killed/survived data
- test declaration locations
- public symbol references

It must not use AI to decide which tests are required.

## Selection Record

Each mutant report must include:

```json
{
  "test_selection": {
    "strategy": "same_file_then_package",
    "selected": [
      {
        "file": "src/range.zig",
        "name": "get rejects out of bounds",
        "line": 18
      }
    ],
    "commands": [
      "zig test src/range.zig"
    ],
    "fallback_used": false
  }
}
```

## Determinism Rules

Selection must:

- sort tests by file, line, name
- preserve configured command order for configured commands
- sort only discovered/generated same-file commands by normalized path and test name before merging with configured fallback commands
- use stable path normalization
- produce the same selection regardless of worker count

For `same_file_then_package`, generated same-file commands run before configured fallback commands when same-file evidence exists. When fallback is required, configured commands run in config order so fail-fast evidence matches the user's declared command sequence.

## Fail-Fast Interaction

Fail-fast may stop executing more commands for a single mutant after it is killed. It must still record:

- which command killed it
- which commands were not run because fail-fast applied
- configured fail-fast policy

Fail-fast must not change candidate generation or mutant IDs.

## Testing Requirements

Test selection tests must cover:

- same-file selection
- fallback to full command
- deterministic ordering
- excluded test mutation targets
- multiple test commands
- fail-fast evidence recording
- impact graph disabled behavior
