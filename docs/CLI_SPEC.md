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
```

Global options parse before command dispatch. Unknown options fail with exit code `2` and `ZNTL_CLI_INVALID_OPTION`.

| Option | Applies to | Notes |
| --- | --- | --- |
| `--no-color` | all terminal output | Needed for stable help and error snapshots. |
| `--config <path>` | `check`, `run`, `list-mutants`, `doctest` | Shared parser; command-specific behavior belongs to each command. |
| `--root <path>` | `check` and other project commands | Normalizes project-relative paths before command dispatch. |

`--verbose` and `--quiet` are **not** global options: they are command-local to `zentinel run` (parsed after the subcommand, e.g. `zentinel run --verbose`) and select the text-report verbosity; `--quiet` additionally suppresses the per-mutant progress lines on stderr. They must not change deterministic JSON fields or hide errors/required evidence. See the `run` section below.

`--format` is not a global option in v1. It is command-local where documented, such as `zentinel doctest --format <text|json>`. `doctest` output is `text` or `json` only; streaming `jsonl` and `junit` are mutation-run report formats, not doctest formats. Mutation runs use `--report <text|json|jsonl|junit>` to avoid ambiguity.

## Exit Codes

| Code | Meaning |
| --- | --- |
| `0` | Command completed successfully. |
| `1` | Deterministic command completed but found failing evidence, including mutation survivors under fail-on-survivors or doctest failures. |
| `2` | CLI usage or config error. |
| `3` | Baseline tests failed. |
| `4` | Internal zentinel error or invalid mutant generation. |

AI-only commands never have their own exit code. An AI failure is a
usage/advisory failure — it never alters a deterministic report — so it exits `2`
(the CLI usage code) and is distinguished only by its `ZNTL_AI_*` stderr token
(for example `ZNTL_AI_PROVIDER_NOT_ALLOWED` or `ZNTL_AI_RESPONSE_INVALID`).

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

Run 'zentinel <command> --help' for command-specific options.
```

Help output is snapshot-tested and lists the doctest subcommands and report formats so `--help` agrees with the implemented CLI surface.

## Per-command `--help`

Every command with a documented option surface — `run`, `init`, `check`, `list-mutants`, `doctest`, `explain`, `suggest`, `review-tests`, and `version` — accepts `--help` (or `-h`) after the command name. It prints that command's usage block to stdout and exits `0`. Each block contains a one-line description, a usage line, and the command's options with one-line explanations; option lists mirror the owning parsers exactly, so a flag must exist in the parser before it is documented in help.

A help request anywhere after the command name takes precedence over option parsing, so `zentinel run --report json --help` prints help instead of running and `zentinel run --help` never fails with `ZNTL_CLI_INVALID_OPTION`. Per-command help is deterministic plain text (no ANSI) and is routed before config loading, so it works without a `zentinel.toml`. An unknown command keeps its deterministic `ZNTL_CLI_UNKNOWN_COMMAND` failure even when `--help` follows it.

## `version`

```bash cli
zentinel version
```

```text output
zentinel 0.1.0
zig 0.16.0
```

`zentinel version` reports discovered Zig status as environment information, while `zentinel check` treats unsupported or missing Zig as a fatal environment validation failure.

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
--name <name>
--test-command <command>
--backend <ast>
```

`--force` is part of the initial CLI shell. `--test-command` and `--backend <ast>` are implemented after the config parser exists so their output can be validated against `docs/CONFIG_SPEC.md`. Before task 002, task 001 may reject those two options with `ZNTL_CLI_INVALID_OPTION`.

The generated `[project] name` is inferred rather than hardcoded. Precedence:

1. an explicit `--name <name>`;
2. the `.name` field of `build.zig.zon` in the project root, recognizing the forms Zig writes (`.name = .foo`, `.name = .@"foo"`, and the legacy `.name = "foo"`); the zon read is best-effort and lexical, never a dependency on zon validity;
3. the project root directory's basename;
4. the template default `"example"`, used only when none of the above yields a usable name.

A candidate name is usable only when it can be embedded in zentinel's escape-free TOML: non-empty, no `"`, and no control bytes (the same constraint as `--test-command`). An inferred candidate that fails the constraint falls through to the next source; an explicit `--name` that fails it is rejected with exit code `2` and `ZNTL_CLI_INVALID_OPTION`, and no config is written.

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
--backend <ast|zir>
--operator <name>
--format <text|json>
```

Experimental backends require explicit opt-in.

`list-mutants --backend zir` selects the experimental ZIR backend; `--backend ast` remains the stable path. (The `air` backend was retired: AIR-level mutation mapping is infeasible without Zig's `Sema` stage.)

`--backend` is **`list-mutants`-only**. `--backend zir` does **real ZIR lowering for every binary-operator mutation** (task 056, Phases 1-3): it lowers each source file to ZIR via `std.zig.AstGen` and recognizes `equality_swap`/`comparison_boundary` (from `cmp_*`), `logical_and_or` (from `bool_br_and`/`bool_br_or`), and `arithmetic_add_sub`/`arithmetic_mul_div` (from `add`/`sub`/`mul`/`div`) sites, in exact differential parity with the AST recognizers; every other operator and every AstGen-injected operator is an out-of-report diagnostic, never a mutant. The remaining operators are AST-only **by principle**: literal mutations (`boolean_literal`, `integer_literal_boundary`) lower to operand refs (no instruction), and control-flow ones (`error_catch_unreachable`, `optional_orelse_unreachable`, `errdefer_remove`, `loop_boundary`) desugar into multi-instruction patterns the AST node recognizes more cleanly. ZIR is `experimental`, opt-in, and affects only the `list-mutants` listing — never `run`.

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
--changed-only
--diff <ref>
--scope-files <list>
--verbose
--quiet
```

`--verbose` and `--quiet` are command-local to `run` and select the text-report verbosity (`--quiet` prints only the compact summary; `--verbose` lists every mutant). They are mutually exclusive, affect only text rendering and stderr progress, and never change the canonical JSON. They are parsed after the `run` subcommand (`zentinel run --verbose`), not as leading global options.

### Run progress

`run` prints one progress line per mutant to **stderr** as each result completes:

```text
[3/12] killed arithmetic_add_sub src/foo.zig:42
```

The fields are the completion counter over the total mutant count, the mutant's primary-mode status as classified in the parallel mutant phase, its operator, and its `file:line` location. Progress lines:

- go to stderr only; stdout stays reserved for the selected `--report` rendering, byte-for-byte unchanged by progress;
- are emitted in completion order — under `--jobs > 1` the counter reflects whichever mutant finished, while report ordering stays deterministic and index-addressed;
- are suppressed by `--quiet`;
- are plain text: no ANSI, no spinner, no terminal-width or TTY behavior;
- are advisory output, never part of any report, exit code, or `--output` artifact.

`run` always uses the stable AST backend and does **not** accept `--backend`: `zentinel run --backend <...>` is rejected deterministically with exit code `2` and a clear message that `--backend` is `list-mutants`-only (it is not a silently ignored no-op). The experimental ZIR backend never participates in a run.

## Run Options

A documented option must not be silently ignored; command dispatch must reject unsupported run options deterministically with exit code `2`.

| Option | Notes |
| --- | --- |
| `--config <path>` | Reuses the shared config-path parser. |
| `--operator <name>` | Filters candidates to one documented operator. |
| `--mutant <id>` | Runs one durable mutant ID after candidate generation. |
| `--fail-on-survivors` | Changes the run command exit code to `1` when survivors are present. |
| `--report <text|json|jsonl|junit>` | Selects the stdout report rendering. |
| `--output <path>` | Writes the **canonical JSON** report to the configured or explicit output path (this is the durable machine artifact that `--input-report` consumers read back). `--report` selects only the **stdout** rendering; it does not change the format written to `--output`. So `--output ci.json --report junit` writes canonical JSON to `ci.json` and prints JUnit to stdout. |
| `--no-cache` | Disables zentinel result-cache reads and writes for the invocation; Zig build-cache isolation is handled by the runner and worker pool. |
| `--jobs <n>` | Overrides normalized `run.jobs` for the invocation. |
| `--mode <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>` | Overrides configured `zig.modes` for a single-mode run. |
| `--changed-only` | Restricts the run to source files changed in the working tree, derived from git. |
| `--diff <ref>` | Restricts the run to source files changed relative to the given git ref (e.g. a branch or commit). |
| `--scope-files <list>` | Restricts the run to an explicit comma-separated list of source files. |

`--changed-only`, `--diff <ref>`, and `--scope-files <list>` are three mutually exclusive ways to derive a single diff scope. Combining any two of them is ambiguous (which base or list wins?) and is rejected deterministically with exit code `2`. When a derived scope matches no eligible source files, the run proceeds with 0 mutants and emits the advisory `ZNTL_DIFF_SCOPE_EMPTY` note on stderr; when changed files cannot be derived from git, it fails with `ZNTL_DIFF_SCOPE_FAILED`.

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

`<mutant-ref>` accepts either a durable mutant ID such as `m_01hr7p6h0v2fj3drdzt9k2a0xe` or the display ID from the selected report, such as `42`. Display IDs are scoped to the report named by `--input-report` and must not be persisted in reports or AI context as durable references.

For doctest AI commands, `--input-report <path>` points to a deterministic doctest report. `zentinel doctest explain <case-ref>` and `zentinel doctest review-snapshot <case-ref>` require the selected report and default to `zig-out/zentinel/doctest/report.json` when omitted; a missing default report is a usage error. `zentinel doctest suggest <doc-path>` and `zentinel doctest suggest-missing [--file <doc-path>]` do not require a report; when `--input-report` is provided, the report is optional context and must be validated before use. `zentinel doctest explain-survivor <survivor-ref>` requires a mutation-aware doctest report and resolves a `ds_...` survivor from it; it defaults to the same `zig-out/zentinel/doctest/report.json` path when `--input-report` is omitted. All `--input-report`, doctest `--file`, and documentation positional read paths must remain project-relative and must not traverse symlinked components.

`zentinel doctest --mutate --file <doc-path>` runs the mutation-aware doctest pass over the documentation file: it mutates each passing `zig test` doctest snippet, runs it, and writes the stable `zentinel.doctest.report.v1` report (durable `dm_...` mutation ids and `ds_...` survivor refs) to `zig-out/zentinel/doctest/report.json` (the default `explain-survivor` path), as well as to stdout. The input doc path, generated scratch path, and persisted report path use the shared project-root containment guard before filesystem access. Passing `--mutate` is the explicit opt-in; surviving documentation mutants are reported, not a failure, and are resolved advisorily via `zentinel doctest explain-survivor <ds_...>`. So the end-to-end path — `doctest --mutate` to produce the report, then `doctest explain-survivor` to resolve a survivor — is reachable; the subcommand never dead-ends with no possible input.

`<case-ref>` accepts either a durable doctest case ID such as `dt_01hr7p6h0v2fj3drdzt9k2a0xe` or a source ref such as `docs/CLI_SPEC.md:47[:help-output]` resolved against the current extraction or selected doctest report. Doctest source-ref examples are illustrative; executable fixtures must derive source refs from current extraction metadata instead of copying hard-coded line numbers from this document. Source refs resolve only against the case anchor line, which is the first executable or producer block in the grouped case. Lines that point only at secondary expectation blocks must fail with `ZNTL_DOCTEST_CASE_NOT_FOUND` instead of guessing the producer. Source refs are selectors, not durable references, and must not be persisted in reports or AI context as canonical IDs.

Doctest AI subcommands are user-facing CLI commands. `zentinel doctest explain <case-ref>` explains a failing doctest case from the selected doctest report. `zentinel doctest suggest <doc-path>` suggests executable examples for one project-relative docs path. `zentinel doctest review-snapshot <case-ref>` summarizes normalized expected/actual snapshot differences from exact `case.result.snapshot` evidence for one report case. `zentinel doctest suggest-missing [--file <doc-path>]` suggests public docs that need executable examples. `zentinel doctest explain-survivor <survivor-ref>` explains a mutation-aware doctest survivor. None of these commands edit documentation, snapshots, or deterministic doctest reports.

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
