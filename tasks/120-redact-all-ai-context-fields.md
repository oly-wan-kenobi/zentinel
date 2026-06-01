# 120 Redact All AI Context Fields

Sequential guard: start this task only after task `119` is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

> Source: adversarial audit finding F-4 (High, AI-boundary leak). Redaction/normalization is wired only to evidence excerpts; the source-, diff-, and path-bearing context fields pass through verbatim. `mutant.file`, `mutant.original`, `mutant.replacement`, and `mutant.diff` are copied unredacted (src/ai/command.zig:366-370), as are `doctest.file`, `source_ref`, and `mutation_case.mutated_diff` (src/ai/doctest_command.zig:1031-1041,1005-1008,371-374). docs/AI_CONTEXT_SCHEMA.md:298 promises "normalize absolute paths to project-relative paths", which is never implemented for these fields, and `privacy.redactions_applied` is reported empty even when paths/secrets are present. Confirmed on the real binary: `zentinel explain m_evil --ai-provider stub --input-report report.json` echoes an absolute path containing a secret-looking segment verbatim to stdout. The determinism boundary (AI cannot set status/exit_code/failure_kind) holds and must be preserved; this task only closes the redaction-scope gap.

## Goal

Apply absolute-path normalization and secret scrubbing to every field that enters the AI context (file paths, `original`/`replacement`/`diff`/`mutated_diff`), and make `privacy.redactions_applied` reflect what was actually redacted, so no absolute path or secret-looking token survives into the context or rendered output.

## Scope

- Extend the existing redaction/path-normalization to the source-, diff-, and path-bearing context fields in both the mutation and doctest AI flows.
- Keep `redactions_applied` truthful.
- Do not alter the deterministic core or let AI output influence any deterministic field.

## Files allowed to modify

- `src/ai/context.zig`
- `src/ai/command.zig`
- `src/ai/doctest_command.zig`
- `src/ai/redaction.zig`
- `docs/AI_CONTEXT_SCHEMA.md`
- `test/ai_context_test.zig`
- `test/ai_command_test.zig`
- `artifacts/pipeline/120/**`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/run_command.zig`
- `src/runner.zig`
- `src/report.zig`
- `build.zig`
- `build.zig.zon`

## Required tests

- Add a failing test that builds an AI context from a report whose `file` is an absolute path and whose `diff`/`original` contains a secret-looking token, and asserts no absolute path or token survives into the context and `redactions_applied` is non-empty (today both leak and the list is empty). The test must fail before the fix.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Acceptance criteria

- `explain`, `suggest`, `review-tests`, and the doctest-survivor context redact paths and secrets in all fields, not just evidence excerpts.
- `privacy.redactions_applied` records every redaction performed and is non-empty when redactions occur.
- The rendered AI command output no longer echoes absolute paths or secret-looking tokens.
- The determinism boundary is unchanged: AI output still cannot set `status`, `exit_code`, or `failure_kind`.

## Non-goals

- Redacting the mutated code to the point of uselessness; the AI is meant to see the code, so prefer path-normalization plus secret scrubbing. If the right redaction depth for `original`/`replacement` is genuinely a product judgement, record the smallest prerequisite or request a decision per the Autonomous Blocker Resolution protocol rather than guessing.
- Any change to the deterministic run/report path.

## Suggested implementation approach

1. Route every context field that can carry a path or source through the existing `redaction` helpers (path-normalize absolute paths to project-relative, scrub secret-looking tokens) before it is written to the context.
2. Populate `redactions_applied` from the redactions actually performed.
3. Update docs/AI_CONTEXT_SCHEMA.md to describe the now-implemented normalization honestly.

## Dogfooding implications

zentinel's own advisory AI commands stop leaking absolute developer paths and any secret-looking strings from analyzed source into the AI context and terminal output.

## Follow-up tasks

- None predefined.
