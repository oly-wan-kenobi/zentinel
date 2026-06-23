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
| `impact_graph` | Reserved / not yet implemented. **Rejected by config validation** — see [Impact Graph](#impact-graph). |

Default:

```text
same_file_then_package
```

## Same-File Tests

Zig often colocates tests and implementation. For a mutation in `src/range.zig`, zentinel may select:

```bash
zig test src/range.zig
```

Generated same-file selected commands are authorized generated selected test commands, not arbitrary AI or shell output. The rendered command is `zig test <file>` with the project-relative path quoted when needed so spaces and literal glob characters in file names are preserved as one argv item. A generated selected command must pass an unmutated preflight before it can classify a mutant. If the command was not part of the baseline command set, zentinel first runs it against the unmodified project, records that preflight evidence, and uses the command for mutant classification only if the preflight passes. When that preflight fails, times out, crashes the compiler, or cannot be constructed as valid argv, zentinel falls back to the configured command set and records `fallback_used = true`.

Report writers must copy generated-command preflight evidence into `test_selection.preflight_commands`. Configured baseline commands may leave that array empty; generated commands must have a matching `phase = "selection_preflight"` preflight entry before their mutant command evidence can affect `result.status`. A generated command construction/parsing failure is recorded as a skipped selection-preflight command with a deterministic `skip_reason`, then selection falls back.

Same-file test bodies are not mutation targets by default.

## Build Tests

For projects that require `build.zig`, selection may run:

```bash
zig build test
```

When selection cannot prove a narrower command, it must fall back to configured full test commands.

## Soundness Guarantee

A narrowed selection is a performance optimization and must never make a mutant *look* survived when the user's configured command set would kill it. A generated `zig test <file>` command is weaker than the configured suite: a mutant whose function is exercised only by a sibling `*_test.zig` survives the same-file command but is killed by `zig build test`. Recording that mutant as `survived` would be a false survivor, inflating the survivor count and deflating the mutation score.

Therefore the default `same_file_then_package` strategy (and any narrowed strategy, including `same_file` and `impact_graph`) is **sound**: a `survived` verdict produced by a narrowed selection is **re-verified against the full configured command set before it is recorded**.

- When a mutant survives a narrowed selection, zentinel re-runs the configured commands for that mutant. The mutant keeps `survived` only if the configured suite also fails to kill it; otherwise it is recorded with the verdict the configured suite produced (e.g. `killed`).
- Only survivors of a narrowed selection pay this re-verification cost. A selection that already runs the configured set — the `all` strategy, or a same-file selection that fell back — runs no extra commands.
- The configured re-verification commands are appended to the mutant's `result.commands` (at `phase = "mutant"`), so the recorded verdict always reflects the configured suite and the evidence shows it ran. A recorded `survived` therefore means the mutant survived the configured suite, not merely the selected subset.

This guarantee covers the recorded mutant verdict and the derived survivor counts and mutation score. The additive safety-mode matrix (`result.mode_matrix`) reports per-mode statuses for the selected commands and is advisory, not the primary verdict.

## Impact Graph

`impact_graph` is **reserved and not yet implemented**. Its current resolver is an exact alias of `same_file_then_package`, so accepting `selection = "impact_graph"` would record a misleading `impact_graph` strategy in the report for behavior that is really same-file-then-package. To avoid that false strategy label, **config validation rejects `selection = "impact_graph"`** (`invalid_value`); the `Strategy` enum variant and its resolver branch are retained only for forward-compatibility until a real impact-graph resolver lands.

When implemented, `impact_graph` must not be an alias for `same_file_then_package` and must not silently fall back to all tests; its impact set must be deterministic and recorded. Only then will config accept it.

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
    "preflight_commands": [
      {
        "command": {
          "original": "zig test src/range.zig",
          "argv": ["zig", "test", "src/range.zig"],
          "cwd": "<project>",
          "environment_policy": "minimal",
          "shell": false
        },
        "phase": "selection_preflight",
        "status": "passed",
        "exit_code": 0,
        "timed_out": false,
        "failure_kind": "none",
        "duration_ms": 0,
        "evidence": {
          "stdout_excerpt": "",
          "stderr_excerpt": "",
          "failure_summary": ""
        },
        "skip_reason": null
      }
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
