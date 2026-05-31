# CLI Specification

zentinel CLI output should be concise, compiler-native, and deterministic where possible.

## Command Overview

```text
zentinel --help
zentinel version
zentinel init
zentinel check
zentinel list-mutants
zentinel run
zentinel doctest
zentinel doctest explain <case-ref>
zentinel doctest suggest <doc-path>
zentinel doctest review-snapshot <case-ref>
zentinel doctest suggest-missing [--file <doc-path>]
zentinel doctest explain-survivor <survivor-ref>
zentinel explain <mutant-ref>
zentinel suggest <mutant-ref>
zentinel review-tests
```

Phase 0 implements the CLI shell incrementally:

- task 001 implements `--help`, `version`, `init`, and `init --force`
- task 002 adds config-aware `init --test-command` and `init --backend <ast>`
- task 005 adds `check`

The help output may list the full roadmap command set before every command is implemented. A known roadmap command that is not implemented yet must fail deterministically with exit code `2`, error code `ZNTL_CLI_COMMAND_NOT_IMPLEMENTED`, and a message that names the command. A command outside this list fails as `ZNTL_CLI_UNKNOWN_COMMAND`.

## Global Options

```text
--config <path>
--root <path>
--no-color
--verbose
--quiet
```

Global options parse before command dispatch only after their owner task is implemented. Before then, a known future global option must fail with exit code `2` and `ZNTL_CLI_INVALID_OPTION`; unknown options also fail with exit code `2`.

Ownership:

| Option | Owner task | Applies to | Notes |
| --- | --- | --- | --- |
| `--no-color` | `tasks/001-cli-shell.md` | all terminal output | Needed for stable help and error snapshots. |
| `--config <path>` | `tasks/005-version-policy.md` | `check`; reused by `run`, `list-mutants`, and `doctest` as those commands land | Shared parser only; command-specific behavior is added by each command task. |
| `--root <path>` | `tasks/005-version-policy.md` | `check`; reused by later project commands | Normalizes project-relative paths before command dispatch. |
| `--verbose` | `tasks/018-report-renderers.md` | report-producing commands | Must not change deterministic JSON fields. |
| `--quiet` | `tasks/018-report-renderers.md` | report-producing commands | Must not hide errors or required evidence. |

`--format` is not a global option in v1. It is command-local where documented, such as `zentinel doctest --format <text|json|jsonl>`. Mutation runs use `--report <text|json|jsonl|junit>` to avoid ambiguity.

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | Command completed successfully. |
| `1` | Deterministic command completed but found failing evidence, including mutation survivors under fail-on-survivors or doctest failures. |
| `2` | CLI usage or config error. |
| `3` | Baseline tests failed. |
| `4` | Internal zentinel error or invalid mutant generation. |
| `5` | AI provider error for AI-only command. |

## `--help`

```text
zentinel - Zig-native mutation testing

Usage:
  zentinel <command> [options]

Commands:
  init           create zentinel.toml
  version        print version information
  check          validate config and environment
  list-mutants   list generated mutants without running tests
  run            run mutation testing
  doctest        validate executable documentation
  explain        explain one mutant using advisory AI
  suggest        suggest tests for one mutant using advisory AI
  review-tests   review survivors using advisory AI
```

Help output is snapshot-tested.

## `version`

```bash cli
zentinel version
```

```text output
zentinel 0.0.0
zig 0.16.0
```

Task `001` owns only policy-label `zentinel version` output. Until task `005` is complete, task `001` treats version output as policy-only and prints the configured zentinel version and Zig policy label but must not invoke `zig version` or own compatibility diagnostics.

Task `005` adds real Zig discovery to `zentinel version` and `zentinel check`. After task `005`, `zentinel version` reports discovered Zig status as environment information, while `zentinel check` treats unsupported or missing Zig as a fatal environment validation failure.

When Zig is missing, `zentinel version` exits `0`, prints zentinel version on stdout, and reports `ZNTL_ZIG_NOT_FOUND` on stderr because Zig is not required to print the tool version. When Zig is unsupported, `zentinel version` still exits `0`, prints zentinel version on stdout, and reports `ZNTL_ZIG_UNSUPPORTED_VERSION` with detected and required versions on stderr.

When Zig is missing, `zentinel check` exits `2` with `ZNTL_ZIG_NOT_FOUND`. When Zig is unsupported, `zentinel check` exits `2` with `ZNTL_ZIG_UNSUPPORTED_VERSION`.

## `init`

Creates `zentinel.toml` in the project root.

Default output:

```text
created zentinel.toml
```

If the file exists, fail unless `--force` is provided.

Options:

```text
--force
--test-command <command>
--backend <ast>
```

`--force` is part of the initial CLI shell. `--test-command` and `--backend <ast>` are implemented after the config parser exists so their output can be validated against `docs/CONFIG_SPEC.md`. Before task 002, task 001 may reject those two options with `ZNTL_CLI_INVALID_OPTION`.

`init` must not enable AI or experimental backends by default.

## `check`

Validates:

- config file
- Zig version policy
- test commands
- include/exclude globs
- report output directory

It does not generate or run mutants.

## `list-mutants`

Generates candidates and prints them without executing tests.

Useful options:

```text
--backend <ast|zir|air>
--operator <name>
--json
```

Experimental backends require explicit opt-in.

`list-mutants --backend zir` is owned by task `056`; `list-mutants --backend air` is owned by task `057`. Before those tasks land, `list-mutants --backend <zir|air>` must fail deterministically as a known experimental option that is not yet implemented, while `--backend ast` remains the stable path owned by the initial `list-mutants` work.

`--backend` is **`list-mutants`-only**. The experimental ZIR and AIR backends are relabel prototypes that re-tag the stable AST candidate set with `backend = zir|air`; they do no IR-level analysis or lowering (see `docs/ZIR_BACKEND.md`, `docs/AIR_BACKEND.md`). They affect only the `list-mutants` listing's backend labels and never change which mutants are generated or run.

## `run`

Runs mutation testing.

Useful options:

```text
--config <path>
--operator <name>
--mutant <id>
--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>
--jobs <n>
--fail-on-survivors
--report <text|json|jsonl|junit>
--output <path>
--no-cache
```

`run` always uses the stable AST backend and does **not** accept `--backend`: `zentinel run --backend <...>` is rejected deterministically with exit code `2` and a clear message that `--backend` is `list-mutants`-only (it is not a silently ignored no-op). The experimental ZIR/AIR relabel backends never participate in a run.

## Run Option Ownership

`zentinel run` option implementation is intentionally split across tasks. A documented option must not be silently ignored before its owner task lands; command dispatch must reject not-yet-owned run options deterministically with exit code `2`.

| Option | Owner task | Notes |
| --- | --- | --- |
| `--config <path>` | `tasks/016-minimal-run-command.md` | Reuses the shared config-path parser introduced by task `005`. |
| `--operator <name>` | `tasks/016-minimal-run-command.md` | Filters Phase 1 candidates to one documented operator. |
| `--mutant <id>` | `tasks/016-minimal-run-command.md` | Runs one durable mutant ID after candidate generation. |
| `--fail-on-survivors` | `tasks/016-minimal-run-command.md` | Changes the run command exit code to `1` when survivors are present; JUnit survivor-failure rendering is expanded by task `018`. |
| `--report <text|json>` | `tasks/016-minimal-run-command.md` | Phase 1 run output supports text and canonical JSON. |
| `--report <jsonl|junit>` | `tasks/018-report-renderers.md` | Report-renderer task adds streaming JSONL and JUnit. |
| `--output <path>` | `tasks/016-minimal-run-command.md` | Writes the selected run report under the configured or explicit output path. |
| `--no-cache` | `tasks/021-cache-key-design.md` | Disables zentinel result-cache reads and writes for the invocation; Zig build-cache isolation remains governed by runner and worker tasks. |
| `--jobs <n>` | `tasks/050-parallel-worker-pool.md` | Overrides normalized `run.jobs` for the invocation. |
| `--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>` | `tasks/058-safety-mode-matrix.md` | Overrides configured `zig.modes` for a single-mode run. |

Default text output emphasizes survivors and diagnostics, not percentages.

Explicit `--output <path>` inherits the same project-root restriction as `report.output_dir`; paths outside the project root are rejected unless a future policy explicitly allows them.

## AI Commands

AI commands require `ai.enabled = true` or explicit CLI opt-in:

```bash
zentinel explain 42 --input-report zig-out/zentinel/report.json --ai-provider local
zentinel suggest m_01hr7p6h0v2fj3drdzt9k2a0xe --ai-provider stub
zentinel review-tests --input-report zig-out/zentinel/report.json
zentinel doctest explain dt_01hr7p6h0v2fj3drdzt9k2a0xe --ai-provider stub
zentinel doctest suggest docs/CLI_SPEC.md --ai-provider stub
zentinel doctest review-snapshot docs/CLI_SPEC.md:47:help-output --ai-provider stub
zentinel doctest suggest-missing --file docs/CLI_SPEC.md --ai-provider stub
zentinel doctest explain-survivor ds_01hr7p6h0v2fj3drdzt9k2a0xe --ai-provider stub
```

AI command-local options:

```text
--ai-provider <disabled|stub|local|remote>
--input-report <path>
```

`--ai-provider` is command-local to advisory AI commands. Passing `stub`, `local`, or `remote` is explicit CLI opt-in for that invocation. `remote` additionally requires normalized config to set `ai.remote_allowed = true`; otherwise command dispatch fails with `ZNTL_AI_PROVIDER_NOT_ALLOWED`. `disabled` is valid so tests and scripts can assert the disabled path deterministically.

For mutation AI commands, `--input-report <path>` points to a deterministic mutation report and defaults to `zig-out/zentinel/report.json` when omitted. A missing default mutation report is a usage error, not an AI provider error.

`<mutant-ref>` accepts either a durable mutant ID such as `m_01hr7p6h0v2fj3drdzt9k2a0xe` or the display ID from the selected report, such as `42`. Display IDs are scoped to the report named by `--input-report` and must not be persisted in handoffs, reports, or AI context as durable references.

For doctest AI commands, `--input-report <path>` points to a deterministic doctest report. `zentinel doctest explain <case-ref>` and `zentinel doctest review-snapshot <case-ref>` require the selected report and default to `zig-out/zentinel/doctest/report.json` when omitted; a missing default report is a usage error. `zentinel doctest suggest <doc-path>` and `zentinel doctest suggest-missing [--file <doc-path>]` do not require a report; when `--input-report` is provided, the report is optional context and must be validated before use. `zentinel doctest explain-survivor <survivor-ref>` requires a mutation-aware doctest report and resolves a `ds_...` survivor from it; it defaults to the same `zig-out/zentinel/doctest/report.json` path when `--input-report` is omitted.

`zentinel doctest --mutate --file <doc-path>` runs the mutation-aware doctest pass over the documentation file: it mutates each passing `zig test` doctest snippet, runs it, and writes the stable `zentinel.doctest.report.v1` report (durable `dm_...` mutation ids and `ds_...` survivor refs) to `zig-out/zentinel/doctest/report.json` (the default `explain-survivor` path), as well as to stdout. Passing `--mutate` is the explicit opt-in; surviving documentation mutants are reported, not a failure, and are resolved advisorily via `zentinel doctest explain-survivor <ds_...>`. So the end-to-end path — `doctest --mutate` to produce the report, then `doctest explain-survivor` to resolve a survivor — is reachable; the subcommand never dead-ends with no possible input.

`<case-ref>` accepts either a durable doctest case ID such as `dt_01hr7p6h0v2fj3drdzt9k2a0xe` or a source ref such as `docs/CLI_SPEC.md:47[:help-output]` resolved against the current extraction or selected doctest report. Doctest source-ref examples are illustrative; executable fixtures must derive source refs from current extraction metadata instead of copying hard-coded line numbers from this document. Source refs resolve only against the case anchor line, which is the first executable or producer block in the grouped case. Lines that point only at secondary expectation blocks must fail with `ZNTL_DOCTEST_CASE_NOT_FOUND` instead of guessing the producer. Source refs are selectors, not durable references, and must not be persisted in handoffs, reports, or AI context as canonical IDs.

Doctest AI subcommands are user-facing CLI commands because autonomous agents can invoke and test CLI surfaces reliably. `zentinel doctest explain <case-ref>` explains a failing doctest case from the selected doctest report. `zentinel doctest suggest <doc-path>` suggests executable examples for one project-relative docs path. `zentinel doctest review-snapshot <case-ref>` summarizes normalized expected/actual snapshot differences from exact `case.result.snapshot` evidence for one report case. `zentinel doctest suggest-missing [--file <doc-path>]` suggests public docs that need executable examples. `zentinel doctest explain-survivor <survivor-ref>` explains a mutation-aware doctest survivor after task `067` implements that deferred flow. None of these commands edit documentation, snapshots, or deterministic doctest reports.

If AI is disabled, commands fail with a clear message:

```text
AI assistance is disabled. Enable [ai] in zentinel.toml or pass an explicit provider.
```

AI command failures must not alter deterministic report files.

## `doctest`

Validates executable documentation examples.

Useful options:

```text
--file <path>
--case <case-ref>
--format <text|json|jsonl>
--mutate
--no-cache
```

Default behavior:

- extract doctest blocks from configured docs
- run normal executable documentation cases
- normalize output before matching
- fail on invalid or failing doctests
- avoid mutation behavior unless `--mutate` is explicit

`--mutate` is experimental until `docs/DOCTEST_MUTATION_STRATEGY.md` stabilization tasks are complete.

## Output Determinism

CLI output that is snapshot-tested must normalize:

- absolute paths
- durations
- Zig version discovery when mocked
- color codes when `--no-color` is used
