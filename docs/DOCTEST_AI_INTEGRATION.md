# Doctest AI Integration

AI can make doctest failures and documentation survivors easier to understand. It remains advisory only.

## Allowed AI Flows

| Flow | Purpose |
| --- | --- |
| `explain_doctest_failure` | Explain why a doctest failed using deterministic evidence. |
| `suggest_doctest` | Suggest an executable example for a public feature. |
| `review_snapshot` | Summarize semantic differences in normalized snapshot output. |
| `suggest_missing_doctests` | Identify public docs lacking executable examples. |
| `explain_doctest_survivor` | Explain a survivor from `doctest --mutate`. |

## CLI Surface

Doctest AI exposes user-facing CLI subcommands so autonomous agents can invoke and test the flows directly:

```bash
zentinel doctest explain <case-ref> [--report <path>] [--ai-provider <disabled|stub|local|remote>]
zentinel doctest suggest <doc-path> [--report <path>] [--ai-provider <disabled|stub|local|remote>]
```

`explain` resolves `<case-ref>` against the selected deterministic doctest report, defaulting to `zig-out/zentinel/doctest/report.json` when `--report` is omitted. `<case-ref>` may be a durable `dt_...` doctest case ID or a source ref such as `docs/CLI_SPEC.md:47[:help-output]`; source refs are selectors only, resolve against the case anchor line, and must resolve to one case in the selected report.

`suggest` accepts a project-relative documentation path and does not require a report. When `--report` is provided, the report is optional context and must be validated before use. Both commands are advisory-only and must not edit documentation, snapshots, or deterministic doctest reports.

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

Doctest AI context extends the existing advisory pattern.

```json
{
  "schema_version": "zentinel.ai.doctest.context.v1",
  "flow": "explain_doctest_failure",
  "doctest": {
    "id": "dt_01hr7p6h0v2fj3drdzt9k2a0xe",
    "file": "docs/CLI_SPEC.md",
    "line_start": 47,
    "kind": "cli",
    "status": "failed"
  },
  "evidence": {
    "command": "zentinel --help",
    "expected": "Usage:",
    "actual": "USAGE:",
    "normalized": true
  },
  "privacy": {
    "remote_allowed": false,
    "redactions_applied": []
  }
}
```

The context must contain only:

- selected doctest blocks
- normalized output excerpts
- deterministic status
- relevant docs path and line numbers
- privacy metadata

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

Agents may use suggestions as drafts, but tests and human-readable docs remain repository-owned artifacts.

## Snapshot Review

AI may compare normalized expected and actual output:

```json
{
  "schema_version": "zentinel.ai.doctest.snapshot_review.response.v1",
  "classification": "wording_change",
  "summary": "The help heading changed from 'Usage' to 'USAGE'.",
  "risk": "This is public CLI text and should be reviewed before updating the snapshot."
}
```

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
