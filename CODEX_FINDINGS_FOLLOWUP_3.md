# Codex Findings Follow-Up 3

Date: 2026-06-01

Scope: read-only adversarial audit of zentinel's mutation correctness and stable-AST backend contract. This audit focused on candidate generation, source spans, test-declaration exclusion, mutator validity, ID derivation, sorting and deduping, sandbox patching, baseline handling, generated-test preflight, mutant classification, reverification, report emission, cache keys, and experimental backend boundaries.

Task state at audit time: no active task. The audit did not update task-control state. This file was added afterward at user request to capture the findings.

## Summary

The stable backend boundary is mostly implemented: `zentinel run --backend` is rejected, and ZIR/AIR are list-only relabel prototypes over the stable AST candidate set. I did not find evidence that AI output controls candidate validity or mutant classification.

The main correctness risks are elsewhere: `run` does not fail fast on an unsupported or missing Zig executable, eligible files and candidates can be silently dropped, two stable mutators can emit the same physical source edit for `while` comparisons, generated-test preflight failure currently falls back instead of producing a skipped mutant, cache keys are too narrow for future result reuse, invalid-candidate validation is not centrally enforced, and output excerpt truncation is byte-based rather than UTF-8 safe.

## Finding 1: `run` Does Not Enforce The Pinned Zig Requirement

Severity: High

Confidence: High

Direct evidence:

- `src/cli.zig:358` says Zig version discovery for `run` is "validated but non-fatal".
- `src/cli.zig:360` calls `discoverZig`.
- `src/cli.zig:361` prints the status line if present.
- `src/cli.zig:363` continues into project discovery instead of returning a fatal error.

Governing contract:

- `docs/FAILURE_MODES.md:21` defines missing Zig as a Zig-version failure mode.
- `docs/FAILURE_MODES.md:23` says commands that require Zig fail before project analysis when Zig is missing.
- `docs/FAILURE_MODES.md:28` defines unsupported Zig as a Zig-version failure mode.
- `docs/FAILURE_MODES.md:30` says commands that require Zig fail before project analysis when Zig is unsupported.
- `docs/ARCHITECTURE.md:157` puts Zig version validation before project model construction.
- `docs/ARCHITECTURE.md:153` pins the stable AST backend version to Zig `0.16.0`.

Inference and failure mode:

- A `run` can continue under an unsupported Zig version, or with no Zig available, and then classify baseline or mutant command outcomes as ordinary command evidence.
- That can make mutation results depend on an unsupported compiler or misrepresent an environment failure as a project baseline/test failure.

Why tests or validators may not catch it:

- `test/check_command_test.zig:134` and `test/check_command_test.zig:142` cover missing/unsupported Zig for `check`, not necessarily `run`.
- `test/run_command_test.zig:592` and `test/run_command_test.zig:593` cover `run --backend` rejection, not fatal Zig version enforcement.
- `scripts/validate_task_system.py` validates task metadata consistency, not runtime Zig policy.

Minimal read-only verification command:

```bash
rg -n "non-fatal|discoverZig|ZNTL_ZIG_NOT_FOUND|ZNTL_ZIG_UNSUPPORTED_VERSION|BackendNotInRun" src test docs
```

Smallest safe remediation direction:

- Route `run` through the same fatal Zig-version gate as `check` before project discovery, while keeping `zentinel version` non-fatal.

## Finding 2: Eligible Files And Candidates Can Be Silently Dropped

Severity: High

Confidence: High

Direct evidence:

- `src/cli.zig:371` skips a discovered file when `readFileAlloc` fails during `run`.
- `src/cli.zig:517` skips a discovered file when `readFileAlloc` fails during `list-mutants`.
- `src/run_command.zig:504` skips files that do not parse.
- `src/list_mutants_command.zig:80` skips files that do not parse.
- `src/run_command.zig:255` skips a candidate when `sourceFor(files, candidate.file)` returns null.

Governing contract:

- `docs/AST_BACKEND.md:17` requires clear diagnostics and no silent candidate loss.
- `docs/FAILURE_MODES.md:63` defines backend parse errors.
- `docs/FAILURE_MODES.md:65` says backend parse failures report file context and emit no mutants for that file.
- `docs/FAILURE_MODES.md:70` defines source mapping failure.
- `docs/FAILURE_MODES.md:72` says source mapping failure must reject the candidate or report an internal backend failure, with no approximate span.
- `docs/INVARIANTS.md:113` says test selection may not hide an executed mutant from the final report.

Inference and failure mode:

- Malformed, unreadable, or source-mapping-broken eligible files can vanish from the candidate universe.
- Mutation totals, survivor counts, and mutation score can look better than reality because the report only summarizes candidates that made it through generation.

Why tests or validators may not catch it:

- `src/report.zig:304` validates only the report entries that are present.
- `src/report.zig:306` checks `summary.total` against `mutants.len`, not against the expected candidate universe.
- Existing parseable fixture tests can pass while unreadable or unparsable source files are omitted.

Minimal read-only verification command:

```bash
rg -n "catch continue|skip files that do not parse|sourceFor\\(files|ZNTL_BACKEND_PARSE_ERROR|ZNTL_BACKEND_SOURCE_MAPPING_FAILED" src test docs
```

Smallest safe remediation direction:

- Replace silent skips with deterministic diagnostics. For `run`, either fail with a documented backend/internal error or emit a documented skipped/invalid audit entry that preserves file context.

## Finding 3: `comparison_boundary` And `loop_boundary` Can Emit The Same Source Edit

Severity: High

Confidence: High

Direct evidence:

- `src/mutators/comparison.zig:39` maps `<` to `<=` for `comparison_boundary`.
- `src/mutators/comparison.zig:40` maps `<=` to `<` for `comparison_boundary`.
- `src/mutators/loop_boundary.zig:50` sends `while_simple` conditions to `whileCond`.
- `src/mutators/loop_boundary.zig:70` applies the same boundary-swap logic to the `while` condition node.
- `src/mutators/loop_boundary.zig:87` records the operator token span for the loop-boundary candidate.
- `src/mutant.zig:116` includes operator name in durable ID derivation.
- `src/mutant.zig:195` dedupes only candidates with identical IDs.

Governing contract:

- `docs/MUTATOR_SPEC.md:388` says when more than one operator could match the same source span, exactly one candidate is emitted.
- `docs/MUTATOR_SPEC.md:392` says a documented precedence rule must exist before two operators are allowed to match the same span.
- `docs/MUTATOR_SPEC.md:373` defines canonical candidate ordering but does not authorize duplicate physical edits.

Inference and failure mode:

- A `while (i < n)` condition can produce both a `comparison_boundary` and a `loop_boundary` mutant with the same span, same original text, and same replacement text.
- Because the operator is part of the ID, the duplicates survive dedupe as distinct durable mutants.
- This inflates totals and can mislead ordering, survivor counts, and equivalent-risk analysis.

Why tests or validators may not catch it:

- `test/mutators/comparison_test.zig:32` checks comparison candidates in isolation.
- `test/mutators/loop_boundary_test.zig:32` checks loop candidates in isolation.
- `test/ast_candidate_ordering_test.zig:58` covers exact duplicate identity only, not cross-operator duplicate physical edits.

Minimal read-only verification command:

```bash
rg -n "comparison_boundary|loop_boundary|Operator Overlap|same source span|sortAndDedupe" src test docs
```

Smallest safe remediation direction:

- Document precedence for while-condition boundary swaps, then restrict the lower-precedence mutator so a combined all-mutators collection cannot emit duplicate `(file, span, original, replacement)` edits.

## Finding 4: Generated-Test Preflight Failure Falls Back Instead Of Skipping The Mutant

Severity: Medium

Confidence: High

Direct evidence:

- `src/test_selection.zig:71` enters same-file selection when discovered tests exist.
- `src/test_selection.zig:72` computes whether preflight passed.
- `src/test_selection.zig:91` comments that failed preflight falls back to configured commands.
- `src/test_selection.zig:101` records configured commands as the selection commands.
- `src/test_selection.zig:105` returns configured commands for execution.
- `test/test_selection_test.zig:88` explicitly tests failed-preflight fallback behavior.
- `test/test_selection_test.zig:98` asserts `fallback_used`.

Governing contract:

- `docs/REPORT_FORMAT.md:242` says a generated selected command may classify a mutant only when its preflight entry passed with `failure_kind = none`.
- `docs/REPORT_FORMAT.md:244` says if generated-command preflight fails, times out, or crashes the compiler, the mutant result must be `skipped` with a deterministic preflight failure reason.
- `docs/INVARIANTS.md:33` says mutant results are determined only by deterministic command evidence.

Inference and failure mode:

- A generated same-file command that fails preflight can still lead to a `killed`, `survived`, `compile_error`, or `timeout` result through configured fallback commands.
- That contradicts the report contract and can change summary counts rather than showing the deterministic preflight failure as `skipped`.

Why tests or validators may not catch it:

- The test suite currently codifies fallback behavior at `test/test_selection_test.zig:88`.
- `src/report.zig:352` validates skip reasons only after a result is already marked `skipped`.
- Report validation does not enforce `preflight failed -> mutant skipped`.

Minimal read-only verification command:

```bash
zig build test --summary all --test-filter "failed preflight falls back"
```

Smallest safe remediation direction:

- Reconcile `docs/TEST_SELECTION.md` and `docs/REPORT_FORMAT.md`. If the report contract remains authoritative, return a deterministic skipped mutant result on generated-command preflight failure and preserve the failed preflight evidence.

## Finding 5: Cache Keys Are Too Narrow For Future Result Reuse

Severity: Medium

Confidence: High

Direct evidence:

- `src/cache.zig:16` defines result-cache key inputs.
- `src/cache.zig:26` includes only one `source_hash`, documented as the mutated file content.
- `src/run_command.zig:334` computes `source_hash` from `job.source`.
- `src/run_command.zig:336` keys by the joined selected commands.
- `src/run_command.zig:338` records only the environment policy label `"minimal"`.
- `src/runner.zig:21` shows the actual minimal environment still copies host values such as `PATH`, `HOME`, `TMPDIR`, `ZIG_GLOBAL_CACHE_DIR`, and `ZIG_LOCAL_CACHE_DIR`.
- `src/cache.zig:106` says Phase 1 result reuse is disabled.

Governing contract:

- `docs/INVARIANTS.md:121` says cache keys include every deterministic input that can affect candidates, selected tests, execution, or report output.
- `docs/REPORT_FORMAT.md:83` says deterministic fields must match for the same repository content, config, Zig version, backend, safety mode, command, and selected tests.
- `docs/TEST_SELECTION.md:58` requires same-file survivors to be reverified against configured commands.

Inference and failure mode:

- If result reuse is enabled later, a helper file, build file, test file, or effective environment change can affect execution without changing this key.
- Reverification can append configured command evidence after a narrowed run, but the key is computed from the initial `job.commands` selection.
- This is not currently a live misclassification path while reuse remains metadata-only.

Why tests or validators may not catch it:

- Metadata-only cache tests can verify key determinism without proving semantic completeness.
- Report comparisons may ignore `diagnostics.cache`, so incomplete cache identity can remain invisible until reuse exists.

Minimal read-only verification command:

```bash
rg -n "source_hash|test_command|environment = \"minimal\"|metadata_only|needsConfiguredReverification" src docs test
```

Smallest safe remediation direction:

- Keep result reuse disabled until the key includes a repository/test/build digest, selected-test identity, effective environment digest, and the final authoritative command set after any survivor reverification.

## Finding 6: Structural Invalid-Candidate Validation Is Not Centrally Enforced

Severity: Medium

Confidence: Medium

Direct evidence:

- `src/mutant.zig:90` defines `isValidCandidate`.
- `src/mutant.zig:91` rejects invalid spans.
- `src/mutant.zig:92` rejects spans whose length does not match `original`.
- `src/mutant.zig:93` rejects no-op replacements.
- `src/ast_backend.zig:142` starts collector `finish`.
- `src/ast_backend.zig:143` assigns IDs.
- `src/ast_backend.zig:144` sorts and dedupes without calling `isValidCandidate`.
- `src/sandbox.zig:33` checks only span bounds.
- `src/sandbox.zig:35` checks only that source text matches `original`.

Governing contract:

- `docs/MUTATOR_SPEC.md:9` says all mutators must preserve syntactically valid Zig unless the operator explicitly allows compile-error mutants.
- `docs/MUTATOR_SPEC.md:12` requires exact source spans.
- `docs/MUTATOR_SPEC.md:25` forbids mutating a file more than once for a single mutant.
- `docs/FAILURE_MODES.md:77` defines mutator invalid candidate.
- `docs/INVARIANTS.md:101` reserves `invalid` for zentinel contract violations, malformed patches, or out-of-range spans.

Inference and failure mode:

- A mutator bug that emits `original == replacement` or another structurally invalid candidate can be assigned an ID and executed.
- A no-op patch can be reported as `survived`, which would not represent exactly one deterministic source edit.
- Current stable mutators mostly appear to avoid this individually, so this is a missing centralized guardrail rather than proof of a currently emitted bad candidate.

Why tests or validators may not catch it:

- Mutator-specific tests can pass while a future mutator violates the shared model contract.
- Sandbox tests catch span mismatch and range errors, but `sandbox.apply` does not reject no-op replacements.
- `src/report.zig:358` validates the shape of an `invalid` result only after something has already been classified as invalid.

Minimal read-only verification command:

```bash
rg -n "isValidCandidate|assignId|sortAndDedupe|sandbox.apply|PatchMismatch" src test docs
```

Smallest safe remediation direction:

- Enforce `Mutant.isValidCandidate` before job creation or inside the mutation runner, and add injected bad-candidate tests for no-op, malformed span, and original-length mismatch cases.

## Finding 7: Command Output Excerpt Truncation Is Not UTF-8 Safe

Severity: Low

Confidence: High

Direct evidence:

- `src/runner.zig:89` defines `boundedExcerpt`.
- `src/runner.zig:90` normalizes captured output.
- `src/runner.zig:91` chooses `min(normalized.len, excerpt_limit)` in bytes.
- `src/runner.zig:92` returns `normalized[0..len]` directly.

Governing contract:

- `docs/SCHEMA_REGISTRY.md:36` says output excerpts must truncate on a safe character boundary before schema validation.
- `docs/REPORT_FORMAT.md:236` says command output excerpts are bounded after normalization.
- `docs/REPORT_FORMAT.md:341` says excerpts are stable deterministic fields for repeated-run comparison.

Inference and failure mode:

- A non-ASCII stdout or stderr excerpt with a multibyte character crossing the 4096-byte boundary can produce invalid UTF-8 or unstable evidence emission.
- This is a report-emission correctness issue rather than a candidate-selection issue.

Why tests or validators may not catch it:

- ASCII-only command-output fixtures will pass.
- Schema validation may fail only when the truncation boundary lands inside a multibyte character.

Minimal read-only verification command:

```bash
rg -n "boundedExcerpt|excerpt_limit|maxLength: 4096|safe character boundary" src docs test
```

Smallest safe remediation direction:

- Truncate normalized output with UTF-8 boundary logic before report serialization and add a fixture with a multibyte character crossing the excerpt limit.

## Positive Evidence

- `src/run_command.zig:189` rejects `--backend` in `run`.
- `src/cli.zig:341` explains that `run` always uses the stable AST backend.
- `src/cli.zig:526` gates `list-mutants --backend zir` behind experimental config handling.
- `src/cli.zig:549` gates `list-mutants --backend air` behind experimental config handling.
- `docs/ARCHITECTURE.md:263` states AST is stable by default and ZIR/AIR are experimental relabel prototypes.
- `src/mutant.zig:108` derives durable IDs from deterministic mutant identity.
- `src/mutant.zig:152` sorts by canonical candidate order.
- `src/sandbox.zig:35` validates that the source bytes at the recorded span exactly match the mutant's `original`.
- `src/mutant_runner.zig:46` maps command evidence to terminal mutant status.
- `src/run_command.zig:230` blocks mutant execution when the baseline fails.
- `src/run_command.zig:273` reverifies narrowed-selection survivors against configured commands when needed.

## Trustworthiness Assessment

Mutation results currently appear trustworthy only under these assumptions:

- the local Zig executable is actually pinned to `0.16.0`,
- every eligible source file is readable and parseable,
- candidate source lookup does not fail,
- the tested code does not hit overlapping `comparison_boundary` and `loop_boundary` sites,
- generated same-file preflight does not fail,
- cache result reuse remains disabled,
- stable mutators continue to avoid structurally invalid no-op candidates.

Under those assumptions, ID derivation, canonical sorting, sandbox original-text validation, baseline blocking, and command-evidence classification are substantially supported by the implementation. Without those assumptions, current mutation results should not be treated as fully trustworthy deterministic correctness evidence.
