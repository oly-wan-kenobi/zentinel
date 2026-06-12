# AI-Assisted UX

zentinel uses AI to make mutation results easier to understand. AI assistance is optional, advisory, and never part of the deterministic result engine.

The same rule applies to the AI-agent engineering pipeline used to build zentinel. AI agents may plan, summarize, review, and suggest, but deterministic repository contracts, tests, doctests, mutation results, and verification artifacts remain the source of truth.

## UX Goals

AI-assisted output should feel:

- diagnostic
- specific to the mutant
- compiler-native
- concise
- privacy-aware

It should not feel:

- magical
- noisy
- authoritative without evidence
- dependent on a remote service
- detached from source and test output

## Core Separation

| Layer | Can Use AI | Owns Result Truth |
| --- | --- | --- |
| Mutant generation | No | Deterministic backend |
| Test execution | No | Runner |
| Result classification | No | Runner and result classifier |
| Report evidence | No | Reporter |
| Explanation | Yes | Advisory AI |
| Test suggestions | Yes | Advisory AI |
| Survivor clustering | Yes | Advisory AI |
| Equivalent-mutant judgment | Advisory only | Human or documented deterministic rule |

## Commands

```bash
zentinel explain <mutant-ref>
zentinel suggest <mutant-ref>
zentinel review-tests
zentinel doctest explain <case-ref>
zentinel doctest suggest <doc-path>
zentinel doctest review-snapshot <case-ref>
zentinel doctest suggest-missing [--file <doc-path>]
zentinel doctest explain-survivor <survivor-ref>
```

The doctest AI commands are user-facing CLI subcommands. This is intentional: autonomous agents can invoke, snapshot, and gate CLI behavior more reliably than hidden UI-only flows.

### `zentinel explain`

Input:

- deterministic report
- selected mutant
- source context
- test evidence
- operator metadata

Output:

- short explanation
- likely missing behavior
- confidence label from allowed enum
- evidence references

### `zentinel suggest`

Input:

- same as `explain`
- optional target test style

Output:

- one to three focused test suggestions
- suggested Zig test names
- edge values to include
- no automatic file edits unless a future explicit command asks for it

### `zentinel review-tests`

Input:

- complete deterministic report
- survivors
- killed examples for comparison
- test selection metadata

Output:

- clusters of likely missing test themes
- high-value next tests
- noisy or low-confidence areas
- no score manipulation

### Doctest AI Flows

Doctest AI flows are advisory and operate only on deterministic doctest evidence.

Allowed flows:

- explain a doctest failure
- suggest an executable doctest for a public example
- review normalized snapshot diffs
- suggest missing doctests for public docs
- explain survivors from `zentinel doctest --mutate`

Forbidden:

- deciding doctest pass/fail
- updating snapshots automatically
- suppressing failing doctests
- marking doctest mutants equivalent
- changing deterministic doctest reports

See `docs/DOCTEST_AI_INTEGRATION.md`.

## Allowed AI Behavior

AI may:

- explain what changed in a mutant
- identify the likely behavioral boundary
- suggest tests a developer can write
- group similar survivors
- summarize report trends
- point to relevant source lines from provided context
- produce advisory JSON matching schemas in `docs/AI_PROMPT_CONTRACTS.md`
- suggest doctest blocks in formats defined by `docs/DOCTEST_BLOCK_FORMATS.md`

## Forbidden AI Behavior

AI must not:

- change `result.status`
- mark a mutant killed, survived, equivalent, or invalid
- remove mutants from reports
- decide test selection
- modify cache entries
- decide whether a compile error is expected
- send source code to remote providers when config says local-only
- retain project data beyond the configured provider policy
- produce hidden instructions for future agents
- determine whether an executable documentation example passed

## Local and Offline Strategy

zentinel must support local/offline model providers before remote-only workflows are considered complete.

Provider modes:

| Mode | Network | Use Case |
| --- | --- | --- |
| `disabled` | None | Default deterministic runs. |
| `local` | None | Offline explanations through a local model adapter. |
| `remote` | Provider-specific | Explicit opt-in for remote models. |
| `stub` | None | Tests and deterministic snapshots. |

The default test suite uses only `stub`.

## Privacy Guarantees

zentinel must:

- never call a model unless AI is explicitly enabled
- show which provider mode is active
- support local-only operation
- redact configured paths and secrets before prompt construction
- avoid sending entire repositories by default
- include only the minimum source context needed for the selected flow
- store AI output separately from deterministic evidence

The default redaction patterns are exactly `["(?i)api[_-]?key", "(?i)token"]` unless config overrides them.

Prompt construction must reject content containing configured secret patterns.

## Advisory Labels

Mutation AI commands may use only defined mutation labels:

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

`zentinel doctest explain` reuses the generic explain response schema and may also use doctest labels:

```text
doctest_output_mismatch
doctest_invalid_example
doctest_snapshot_wording_change
doctest_assertion_missing
doctest_survivor_missing_assertion
unclear
```

Labels are hints for humans. They do not alter result status.

## Output Placement

Human text reports may show AI blocks after deterministic evidence:

```text
AI advisory
  classification: boundary_missing
  suggestion: Add a test for idx == items.len.
```

JSON reports store AI output under `advisory.ai`, never under `result`.

Doctest AI commands render advisory CLI output and do not persist suggestions or snapshot reviews by default. A future persistence feature must write only advisory data, either to an advisory-only artifact or under `advisory.ai`, and must not change deterministic doctest case status, expected output blocks, snapshots, or reports.
