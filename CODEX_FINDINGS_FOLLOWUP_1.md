# Codex Findings Follow-Up 1

Date: 2026-06-01

Scope: read-only adversarial audit of runtime determinism and environment boundaries in zentinel. This audit focused on paths that execute subprocesses, inspect or inherit environment, depend on PATH, use timeouts, capture stdout/stderr, classify command results, or feed execution evidence into reports, doctests, cache keys, or AI context.

Task state at audit time: no active task. `tasks/STATUS.md:5-16` reports active task `none`, next task `none`, deterministic core policy enforced, AI authority over correctness forbidden, and validator scope limited to task-system consistency.

No source, task, or metadata files were changed during the audit.

## Summary

The happy-path `zentinel run` command is stronger than the surrounding adapters: configured commands and generated selected commands are parsed into argv, shell execution is avoided, baseline/preflight/mutant/reverification evidence is structured, and report ordering is canonical.

Runtime execution does not currently appear deterministic enough for autonomous mutation correctness without external assumptions. The main gaps are non-fatal Zig discovery, doctest subprocesses inheriting host state, swallowed workspace errors, unsafe UTF-8 truncation in report/doctest excerpts, coarse cache/environment identity, silent generated/preflight anomalies, and AI context command-evidence synthesis.

## Finding 1: Zig Version Policy Is Non-Fatal On Runtime Paths That Need Zig

Severity: High

Confidence: High

Direct evidence:

- `src/check_command.zig:48-56` treats missing or unsupported Zig as a fatal environment error for `zentinel check`.
- `src/cli.zig:358-363` discovers Zig for `zentinel run`, prints a status line, and continues.
- `src/cli.zig:296-299` records missing Zig as the compiled-in supported Zig version in run observation metadata.
- `src/cli.zig:1015-1019` records missing Zig as the compiled-in supported Zig version in doctest metadata.

Governing contract:

- `docs/ZIG_VERSION_POLICY.md:23-34` says commands that need Zig must run `zig version`, compare against the pinned version, and fail fast when unsupported.
- `docs/INVARIANTS.md:63-67` states zentinel supports exactly Zig `0.16.0`.
- `docs/NON_GOALS.md` rejects support for other Zig versions for this zentinel version.

Inference and failure mode:

- Unsupported or missing Zig can affect baseline, mutant, doctest, or cache evidence while reports still claim `zig_version = "0.16.0"`.
- A missing Zig can become a command failure or crash classification instead of an environment-policy failure.

Why tests or validators may not catch it:

- `test/check_command_test.zig:129-145` covers fatal missing/unsupported Zig only for `check`.
- Run and doctest tests mostly use injected executors or a valid local toolchain.
- `scripts/validate_task_system.py` validates task-system metadata, not runtime Zig discovery semantics.

Minimal read-only verification command:

```bash
rg -n "non-fatal|discoverZig|not_found => zentinel.supported_zig_version|check treats unsupported" src test docs
```

Smallest safe remediation direction:

- Make every Zig-executing runtime path fail before execution unless `zig_version.classify(discoverZig(...)) == .supported`.
- Keep `zentinel version` non-fatal, but do not synthesize `0.16.0` for missing Zig in execution reports.

## Finding 2: Doctest Subprocesses Inherit Host Environment And Have No Timeout

Severity: High

Confidence: High

Direct evidence:

- `src/cli.zig:599-606` executes normal doctest CLI commands with `.environ_map = null`.
- `src/cli.zig:1030` sets normal doctest execution timeout to `.none`.
- `src/cli.zig:1086-1093` executes doctest mutation snippets with `.environ_map = null`.
- `src/cli.zig:1148` sets doctest mutation timeout to `.none`.
- `src/cli.zig:161-172` shows the main mutation runtime path does use a minimal environment map.
- `src/doctest/report.zig:59-65` records doctest command evidence with `environment_policy = minimal` and `shell = false`.

Governing contract:

- `docs/SANDBOX_SECURITY.md:106-117` requires the exact minimal environment allowlist and forced `LC_ALL=C` / `LANG=C`.
- `docs/SANDBOX_SECURITY.md:17-28` requires timeouts and bounded stdout/stderr.
- `docs/DOCTEST_ARCHITECTURE.md:285-310` treats doctest execution result and normalized output as cacheable deterministic surfaces and excludes unsupported Zig results.
- `docs/TDD_POLICY.md:157-179` requires doctest tests to avoid wall-clock timing and network commands.

Inference and failure mode:

- Doctests can depend on secrets, locale, PATH, non-allowlisted variables, or arbitrary host state.
- A hanging doctest or doctest mutation can run indefinitely.
- Doctest reports can claim `minimal` environment while real execution inherited the full developer environment.

Why tests or validators may not catch it:

- `test/doctest_runner_test.zig:28-38` uses a mock executor, so real process environment and timeout behavior are not exercised.
- Shape validators can accept `environment_policy = minimal` without proving the adapter used a minimal environment.

Minimal read-only verification command:

```bash
rg -n "doctestExecFn|doctestMutateRunFn|environ_map = null|timeout = \\.none" src/cli.zig
```

Smallest safe remediation direction:

- Reuse `runner.minimalEnviron` for normal doctest and doctest mutation process execution.
- Apply the configured test timeout or an explicit documented doctest timeout.
- Record a different environment policy only if execution intentionally differs from the minimal policy.

## Finding 3: Workspace And Source-Read Failures Can Be Silently Swallowed

Severity: Medium-high

Confidence: High

Direct evidence:

- `src/cli.zig:239-245` copies files into the per-mutant workspace and ignores copy failures with `catch continue`.
- `src/cli.zig:268-270` ignores workspace cleanup failures with `deleteTree(... ) catch {}`.
- `src/cli.zig:370-372` skips discovered source files that fail `readFileAlloc`.
- `src/cli.zig:516-518` has the same skip-on-read-failure pattern in list-mutants.

Governing contract:

- `docs/DISCIPLINE.md:47` says sandbox cleanup failures must be reported and not hidden behind a successful mutation result.
- `docs/DISCIPLINE.md:59` says Zig command failures must be propagated or recorded as structured evidence.
- `docs/SANDBOX_SECURITY.md:61-79` requires isolated workspaces, per-worker writable paths, and reported cleanup warnings when relevant.

Inference and failure mode:

- A mutant can execute in an incomplete workspace if a source, build, config, or auxiliary file fails to copy.
- Cleanup failure can leave stale workspaces or writable artifacts that affect later execution.
- Source read failures can reduce the candidate set without a structured diagnostic.

Why tests or validators may not catch it:

- `test/integration_run_test.zig:1-9` exercises the real process/workspace/report adapters on a happy path.
- Existing tests do not appear to inject copy, permission, read, or cleanup failures.
- Task-system validation does not model filesystem fault injection.

Minimal read-only verification command:

```bash
rg -n "copyFile\\(.*catch continue|deleteTree\\(.*catch \\{\\}|readFileAlloc\\(.*catch continue" src/cli.zig
```

Smallest safe remediation direction:

- Treat workspace copy/read failures as structured sandbox/internal errors, not successful mutant execution.
- Record cleanup failures as report diagnostics or fail the run if they risk source or workspace contamination.

## Finding 4: Mutation AI Context Does Not Mirror Actual Command Evidence

Severity: Medium

Confidence: High

Direct evidence:

- `src/ai/command.zig:323-331` derives one command status/failure kind from the mutant result and at most the first report command.
- `src/ai/command.zig:332-350` synthesizes a single command with original text `zig build test`, argv `["zig", "build", "test"]`, `timed_out = false`, and result-level evidence.
- `docs/AI_CONTEXT_SCHEMA.md:230-232` requires the AI context `commands` array to mirror mutant command results from the canonical report schema.
- `docs/AI_PROMPT_CONTRACTS.md:98-112` shows command evidence in AI prompts as the actual command object and command result fields.

Governing contract:

- `docs/AI_CONTEXT_SCHEMA.md:226-232` says AI receives status and command evidence as read-only evidence, and `commands` mirrors canonical report command results.
- `docs/DISCIPLINE.md:27-29` makes deterministic classifier evidence authoritative and forbids AI from changing correctness.

Inference and failure mode:

- Advisory AI can see plausible but false execution evidence for same-file generated commands, reverification commands, skipped commands, timeouts, and multi-command results.
- This does not appear to affect deterministic classification, but it can mislead AI-generated explanations or test suggestions.

Why tests or validators may not catch it:

- `test/ai_context_test.zig:149-175` validates command evidence shape, not fidelity to the source report.
- `test/ai_command_test.zig:98-188` validates success, overflow rejection, and redaction behavior, but not preservation of report command arrays.

Minimal read-only verification command:

```bash
rg -n "original = \"zig build test\"|commands\\[0\\] = command|mirrors mutant command results" src/ai docs test
```

Smallest safe remediation direction:

- Build AI context commands by mapping every `result.commands[]` report entry after redaction and capping.
- Preserve original command text, argv, cwd, phase, status, exit code, timeout flag, failure kind, evidence, and skip reason.

## Finding 5: Cache And Environment Identity Is Too Coarse For Host-Sensitive Execution

Severity: Medium

Confidence: Medium-high

Direct evidence:

- `src/runner.zig:18-38` builds the minimal env by copying host `PATH`, `HOME`, `TMPDIR`, `ZIG_GLOBAL_CACHE_DIR`, and `ZIG_LOCAL_CACHE_DIR`, then forcing locale.
- `src/run_command.zig:326-339` computes result cache keys with `.environment = "minimal"` and `.zig_cache_namespace = obs.zig_cache_namespace`.
- `src/cache.zig:16-33` defines cache key inputs without effective PATH, resolved Zig executable identity, HOME, TMPDIR, or exact Zig cache environment values.
- `test/cache_key_test.zig:43-94` varies documented string fields, including `environment`, but not effective inherited environment values.

Governing contract:

- `docs/PERFORMANCE_STRATEGY.md:16-28` requires cache keys to include Zig cache namespace metadata and relevant environment normalization.
- `docs/INVARIANTS.md:121-125` requires cache keys to include every deterministic input that can affect candidates, selected tests, execution, or report output.
- `docs/SANDBOX_SECURITY.md:115-117` documents the allowlisted variables that may flow into execution.

Inference and failure mode:

- Two machines can compute the same result key while resolving a different `zig` executable through PATH or using different Zig cache directories.
- Current risk is lower while result cache reuse remains metadata-only, but it becomes correctness-critical when reuse is enabled.

Why tests or validators may not catch it:

- Cache-key tests assert the current documented input tuple, not host environment sensitivity.
- The validator cannot know which host env values affected child process behavior.

Minimal read-only verification command:

```bash
rg -n "env_allowlist|environment = \"minimal\"|zig_cache_namespace|computeKey|ZIG_LOCAL_CACHE_DIR|PATH" src test docs
```

Smallest safe remediation direction:

- Either remove host-sensitive inherited env from execution, or hash/record normalized effective env and resolved pinned Zig identity in cache/report metadata before any result reuse.
- Prefer per-workspace or per-mutant `ZIG_LOCAL_CACHE_DIR` isolation instead of copying a host override through unchanged.

## Finding 6: Report And Doctest Excerpts Can Split UTF-8 At The Byte Cap

Severity: Medium

Confidence: High

Direct evidence:

- `src/runner.zig:89-92` normalizes command output and slices `normalized[0..len]` at the 4096 byte limit.
- `src/doctest/runner.zig:231-233` slices raw doctest output at the same byte limit.
- `src/ai/context.zig:151-160` has a UTF-8 safe cap helper.
- `test/ai_context_test.zig:212-229` tests safe UTF-8 truncation only for AI context capping.

Governing contract:

- `docs/AI_CONTEXT_SCHEMA.md:232` requires stdout/stderr excerpts to be capped at a safe character boundary before AI context construction.
- `docs/SANDBOX_SECURITY.md:121-124` requires command output excerpts to be bounded to 4096 bytes per stream.
- `docs/REPORT_FORMAT.md:236` requires bounded normalized evidence.

Inference and failure mode:

- Non-ASCII stdout/stderr crossing the byte boundary can produce invalid UTF-8 in reports, doctest snapshots, or AI context input.
- JSON serialization or downstream validators may fail or behave differently depending on exact output content.

Why tests or validators may not catch it:

- `test/report_determinism_test.zig:101-120` covers address/path normalization, not UTF-8 boundary safety.
- Existing safe-boundary tests exercise the AI helper, not the runner or doctest excerpt functions that first capture report evidence.

Minimal read-only verification command:

```bash
rg -n "boundedExcerpt|fn bounded|capExcerpt|utf8ValidateSlice" src test
```

Smallest safe remediation direction:

- Reuse a shared UTF-8-safe truncation helper in `runner.boundedExcerpt` and `doctest.runner.bounded`.
- Add runner and doctest tests with a multi-byte codepoint straddling byte 4096.

## Finding 7: Generated Preflight And Candidate-Source Anomalies Can Disappear Instead Of Becoming Evidence

Severity: Medium

Confidence: Medium

Direct evidence:

- `src/run_command.zig:254-258` silently skips a candidate when `sourceFor(files, candidate.file)` returns null.
- `src/run_command.zig:480-485` treats generated command parse failure as `return null` with a comment that generated commands are always well-formed.
- `docs/TEST_SELECTION.md:36-38` requires generated same-file commands to pass unmutated preflight before classifying a mutant.
- `docs/REPORT_FORMAT.md:238-244` requires generated preflight evidence to appear in `test_selection.preflight_commands`.

Governing contract:

- `docs/INVARIANTS.md:113-117` says test selection must never hide an executed mutant from the final report.
- `docs/DISCIPLINE.md:105` requires handoff and verification artifacts to distinguish failed or skipped commands with reasons.
- `docs/SANDBOX_SECURITY.md:50` authorizes generated same-file commands only when built from normalized paths, parsed directly, and supported by preflight evidence.

Inference and failure mode:

- A generator bug, source mismatch, or file-read race can reduce execution/report coverage without a structured skip, invalid result, or internal error.
- A generated command parser regression can silently fall back instead of exposing an invariant violation.

Why tests or validators may not catch it:

- Selection tests cover passing and failing preflights, but not impossible generated-command parse failures.
- Candidate/source mismatch is not easy to reach through ordinary happy-path fixtures.

Minimal read-only verification command:

```bash
rg -n "orelse continue|generated command is always well-formed|return null" src/run_command.zig test
```

Smallest safe remediation direction:

- Treat generated-command parse failure as an internal invariant error or explicit invalid/skipped evidence.
- Treat missing candidate source as a structured internal/backend error rather than omitting the mutant.

## Overall Determinism Assessment

Runtime execution is not currently deterministic enough for autonomous mutation correctness unless all of these assumptions hold:

- The caller or CI has already enforced Zig `0.16.0`.
- Doctest execution is excluded from correctness gates or wrapped in a controlled environment and timeout.
- Workspace copy, source reads, and cleanup never fail.
- Result cache reuse remains disabled.
- Command output does not hit non-ASCII truncation boundaries.
- Advisory AI is not treated as faithful command-evidence review.

Under those assumptions, the core `zentinel run` path appears substantially deterministic on the happy path because it uses shell-free argv parsing, minimal environment execution, structured command evidence, deterministic classification, survivor reverification, and canonical report ordering.
