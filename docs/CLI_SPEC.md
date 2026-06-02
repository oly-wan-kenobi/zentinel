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

Every command listed in `--help` is implemented. The frozen Phase 0 `dispatch` shell owns only `--help`, `version`, and `init`; the project commands (`check`, `run`, `list-mutants`, `doctest`) and the advisory AI commands are handled by the routing layer, so none of them is a "not implemented" roadmap stub anymore. A command that is not recognized fails deterministically with exit code `2` and `ZNTL_CLI_UNKNOWN_COMMAND`. The `ZNTL_CLI_COMMAND_NOT_IMPLEMENTED` code stays defined in the error taxonomy for any future roadmap command added before its handler lands, but no shipped command returns it.

## External Zig binary requirement

zentinel embeds the `std.zig.Ast` parser, so mutant *generation* never shells out to `zig`. The external `zig` binary is only needed to compile and run code. Each command falls into exactly one of three groups; a new command MUST be placed in one of them explicitly (this is the authoritative list — `FAILURE_MODES.md` F-001 references it):

- **Require the external `zig` binary** — the command aborts before project analysis when `zig` is absent or its version is outside the pinned `0.16.0` policy:
  - `check` — exits `2` with `ZNTL_ZIG_NOT_FOUND` before analysis; reporting the discovered Zig's compatibility is the command's whole job.
  - `run` — pre-flights the Zig version gate (`zig_version.fatalStatusLine`) before mutating, because it compiles and runs the test suite.
  - `doctest` and `doctest --mutate` — pre-flight the same gate, because they compile and run extracted documentation code.
- **Discover `zig` but never fatal on it** — informational status only; the command always proceeds and its exit code is independent of Zig:
  - `version` — prints the discovered-Zig status as non-fatal environment info on stderr and still exits `0`.
  - the advisory AI commands `explain`, `suggest`, `review-tests`, and the doctest AI subcommands (`doctest explain` / `suggest` / `review-snapshot` / `suggest-missing` / `explain-survivor`) — use the discovered Zig only as a `supported`/`unknown` label.
- **Do not use the external `zig` binary at all**:
  - `list-mutants` — generates candidates with the embedded `std.zig.Ast` parser only; it never invokes `zig`, so it runs even when no `zig` is on `PATH`.
  - `init` — writes `zentinel.toml`; no Zig is involved.

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

`--format` is not a global option in v1. It is command-local where documented, such as `zentinel doctest --format <text|json>`. `doctest` output is `text` or `json` only; streaming `jsonl` and `junit` are mutation-run report formats, not doctest formats. Mutation runs use `--report <text|json|jsonl|junit>` to avoid ambiguity.

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

Doctest subcommands (advisory AI is opt-in):
  doctest explain <case-ref>            explain a failing doctest case
  doctest suggest <doc-path>            suggest examples for a doc
  doctest review-snapshot <case-ref>    review snapshot differences
  doctest suggest-missing [--file ...]  list public docs needing examples
  doctest explain-survivor <ref>        explain a mutation-aware survivor
  doctest --mutate --file <doc-path>    run the mutation-aware doctest pass

Report formats:
  run --report <text|json|jsonl|junit>
  doctest --format <text|json>
```

Help output is snapshot-tested and lists the doctest subcommands and report formats so `--help` agrees with the implemented CLI surface.

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

`--backend` is **`list-mutants`-only**. `--backend zir` does **real ZIR lowering for comparison operators** (task 056, Phase 1): it lowers each source file to ZIR via `std.zig.AstGen` and recognizes `equality_swap`/`comparison_boundary` sites from the `cmp_*` instructions, in exact differential parity with the AST recognizer; every other operator and every AstGen-injected comparison is an out-of-report diagnostic, never a mutant. `--backend air` is still a relabel prototype that re-tags the stable AST candidate set with `backend = air` and does no IR lowering (see `docs/ZIR_BACKEND.md`, `docs/AIR_BACKEND.md`). Both are `experimental`, opt-in, and affect only the `list-mutants` listing — never `run`.

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

`run` always uses the stable AST backend and does **not** accept `--backend`: `zentinel run --backend <...>` is rejected deterministically with exit code `2` and a clear message that `--backend` is `list-mutants`-only (it is not a silently ignored no-op). The experimental ZIR/AIR backends never participate in a run.

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

For doctest AI commands, `--input-report <path>` points to a deterministic doctest report. `zentinel doctest explain <case-ref>` and `zentinel doctest review-snapshot <case-ref>` require the selected report and default to `zig-out/zentinel/doctest/report.json` when omitted; a missing default report is a usage error. `zentinel doctest suggest <doc-path>` and `zentinel doctest suggest-missing [--file <doc-path>]` do not require a report; when `--input-report` is provided, the report is optional context and must be validated before use. `zentinel doctest explain-survivor <survivor-ref>` requires a mutation-aware doctest report and resolves a `ds_...` survivor from it; it defaults to the same `zig-out/zentinel/doctest/report.json` path when `--input-report` is omitted. All `--input-report`, doctest `--file`, and documentation positional read paths must remain project-relative and must not traverse symlinked components.

`zentinel doctest --mutate --file <doc-path>` runs the mutation-aware doctest pass over the documentation file: it mutates each passing `zig test` doctest snippet, runs it, and writes the stable `zentinel.doctest.report.v1` report (durable `dm_...` mutation ids and `ds_...` survivor refs) to `zig-out/zentinel/doctest/report.json` (the default `explain-survivor` path), as well as to stdout. The input doc path, generated scratch path, and persisted report path use the shared project-root containment guard before filesystem access. Passing `--mutate` is the explicit opt-in; surviving documentation mutants are reported, not a failure, and are resolved advisorily via `zentinel doctest explain-survivor <ds_...>`. So the end-to-end path — `doctest --mutate` to produce the report, then `doctest explain-survivor` to resolve a survivor — is reachable; the subcommand never dead-ends with no possible input.

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
--format <text|json>
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
