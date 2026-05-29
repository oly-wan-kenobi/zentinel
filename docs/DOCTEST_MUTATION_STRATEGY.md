# Doctest Mutation Strategy

`zentinel doctest --mutate` makes documentation examples mutation-aware. It checks whether executable examples are strong enough to detect the kinds of changes the docs claim to guard against.

This is a long-term feature. Normal doctest execution must be stable before mutation-aware doctests are enabled.

## Goals

- Treat documentation examples as behavioral contracts.
- Verify mutator specs with executable before/after examples.
- Detect weak documentation examples that compile and pass but fail to catch meaningful mutations.
- Report documentation survivors in the same diagnostic style as source survivors.
- Keep AI advisory and never authoritative.

## Command

```bash
zentinel doctest --mutate
```

Planned options:

```text
--operator <name>
--case <case-ref>
--file <path>
--format <text|json>
--fail-on-survivors
```

`--format` intentionally matches normal `zentinel doctest` output selection. `--input-report <path>` is used by advisory commands that read an existing deterministic report.

## Mutation-Aware Documentation

Mutation-aware docs use paired blocks:

````md
### Boundary comparison mutation

```zig before
if (idx >= len) return error.OutOfBounds;
```

```zig after
if (idx > len) return error.OutOfBounds;
```
````

The pair documents a mutator transformation. Future doctest mutation mode validates:

- the `before` block is recognized by the mutator
- the generated replacement matches the `after` block
- the operator metadata matches the surrounding spec
- fixture assertions kill or expose the mutant as expected

## Mutating Example Snippets

Executable examples may be mutation-tested:

````md
```zig test case:range-boundary
const std = @import("std");

fn get(items: []const u8, idx: usize) !u8 {
    if (idx >= items.len) return error.OutOfBounds;
    return items[idx];
}

test "rejects index equal to length" {
    const items = [_]u8{1, 2, 3};
    try std.testing.expectError(error.OutOfBounds, get(&items, 3));
}
```
````

Mutation mode may apply `comparison_boundary` to the example and require the doctest assertion to fail.

## Behavioral Assertions

Mutation-aware doctests are only meaningful when examples contain assertions.

Strong examples:

- `zig test` with `std.testing.expect`
- CLI block with exact `text output`
- CLI block with `json expected`
- config failure block with expected diagnostic

Weak examples:

- compile-only `zig` snippets
- CLI command without expected output
- JSON example not tied to a producer

Mutation mode may skip weak examples with reason:

```text
no_behavioral_assertion
```

## Survivor Reporting

Doctest mutation survivor example:

```text
survived doctest docs/MUTATOR_SPEC.md:120 comparison_boundary
  - if (idx >= len) return error.OutOfBounds;
  + if (idx > len) return error.OutOfBounds;
  doctest case passed after mutation: range-boundary
  likely focus: add an example for idx == len
```

JSON report fields should reuse the shared mutant model and add doctest context:

```json
{
  "kind": "mutation",
  "status": "survived",
  "mutation": {
    "mutant_id": "m_01hr7p6h0v2fj3drdzt9k2a0xe",
    "doctest_case_id": "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
    "survivor_ref": "ds_01hr7p6h0v2fj3drdzt9k2a0xe",
    "operator": "comparison_boundary",
    "operator_stability": "stable",
    "backend": "ast",
    "backend_stability": "stable",
    "doc_file": "docs/MUTATOR_SPEC.md",
    "doc_line": 120,
    "source_ref": "docs/MUTATOR_SPEC.md:120:range-boundary",
    "mutated_diff": [
      "- if (idx >= len) return error.OutOfBounds;",
      "+ if (idx > len) return error.OutOfBounds;"
    ],
    "runner_evidence": {
      "status": "survived",
      "command": {
        "original": "zig test src/doctest.zig",
        "argv": ["zig", "test", "src/doctest.zig"],
        "cwd": "<project>",
        "environment_policy": "minimal",
        "shell": false
      },
      "exit_code": 0,
      "timed_out": false,
      "failure_kind": "none",
      "stdout_excerpt": "",
      "stderr_excerpt": "",
      "failure_summary": "",
      "skip_reason": null
    }
  }
}
```

The exact field contract, including `ds_` survivor-ref derivation, lives in `docs/DOCTEST_SPEC.md`.

The mutation-aware doctest runner evidence object is closed and includes `failure_kind` so survivor assistance can distinguish compile errors, test failures, timeouts, compiler crashes, skips, and clean execution without inferring from prose.

## Mutation Score for Docs

Documentation mutation score is allowed only as a secondary summary.

Preferred summary:

```text
2 documentation survivors need stronger examples
```

Allowed secondary detail:

```text
doctest mutation coverage: 8 killed, 2 survived
```

Do not make a percentage the headline.

## Executable Mutator Specs

Mutator specs should evolve toward executable examples.

Example:

````md
### `comparison_boundary`

```zig before
if (idx >= len) return error.OutOfBounds;
```

```zig after
if (idx > len) return error.OutOfBounds;
```

```zig test
const std = @import("std");

test "boundary equality is covered" {
    const len: usize = 3;
    const idx: usize = 3;
    try std.testing.expect(idx >= len);
}
```
````

Long-term validation:

- before/after transformation matches mutator output
- test block kills the transformed behavior when applicable
- report links survivor to the documentation example

## Deterministic Requirements

Mutation-aware doctests must preserve:

- stable doctest case IDs
- stable doctest survivor refs
- stable mutant IDs
- stable report order
- deterministic workspace generation
- deterministic test selection
- deterministic timeout handling

Worker count must not affect output.

## Staging

1. Normal doctest extraction and execution.
2. Executable CLI/config/report docs.
3. Executable mutator before/after examples.
4. `doctest --mutate` for snippets only.
5. `doctest --mutate` for docs linked to fixture projects.
6. Dogfood mutation-aware doctests in CI.

## AI Role

AI may:

- explain a documentation survivor
- suggest a stronger doctest
- classify weak examples
- cluster repeated documentation survivor themes

AI must not:

- mark documentation mutants killed or survived
- decide that a documentation mutant is equivalent
- update expected snapshots without a task
- suppress weak examples automatically
