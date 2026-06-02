# Deep Review — Fix Ledger

Remediation tracker for the findings in [DEEP_REVIEW.md](DEEP_REVIEW.md): **67 confirmed + 17 suspected = 84 items**.

## How to use (with `/loop`)
- **Pick rule:** the FIRST item below whose status is `todo`, read top-to-bottom (High → Medium → Low → Suspected). High is in true priority order; M/L/S are numeric.
- **Statuses:** `todo` · `wip` · `done` · `refuted` (suspected non-bugs, with a reason) · `info` (nothing to fix).
- **Definition of done (per item):** behavior fixed → a regression test that *fails pre-fix and passes post-fix* (assert the specific bucket/mutant/output bytes, never aggregate counts) → `zig build` + full `zig test` green via the zigars MCP → committed with the finding id → this row updated to `done` + short commit hash.
- Read the finding's full Evidence / Tool confirmation / Why / Repro / Suggested-fix in DEEP_REVIEW.md before touching code. Absolute paths there map to repo-relative.
- `[rel: Hx]` = closely related to that High finding; fix together when cheap.

**Progress:** 10/67 confirmed fixed · 0/17 suspected resolved  _(update this line as you go)_

---

## High — fix first (priority order)
- [x] `done` **H4** · commit `4cb4c30` · isCompileFailure "passed;" marker heuristic unreliable under `zig build test` → kill/compile-error misclassification — src/runner.zig
- [x] `done` **H1** · commit `a6a8d16` · integer_literal_boundary / loop_boundary i128 overflow panic on a max-value decimal literal → whole-tool denial — src/mutators/integer_boundary.zig, src/mutators/loop_boundary.zig
- [x] `done` **H5** · commit `f82b17e` · safety_modes.buildFlag is dead code; every `--mode` runs identical Debug — src/run_command.zig, src/safety_modes.zig
- [x] `done` **H3** · commit `381f857` · parallel setupWorkspace walks the live project root, races sibling workers → spurious `invalid` mutants (hides survivors) — src/cli.zig:240-260
- [x] `done` **H2** · commit `2c16ef4` · errdefer_remove emits a dangling-semicolon (invalid) mutant → guaranteed compile_error — src/mutators/error_path.zig:86-118

## Medium
- [x] `done` **M1** · commit `6b57a69` · error_catch_unreachable emits guaranteed compile_error at every catch-with-capture site (unused capture) — src/mutators/error_path.zig `[rel: H2]`
- [x] `done` **M2** · commit `89f4ff7` · copyExcluded path-prefix over-match drops sibling-dir source files → writeFile fails → mutant `.invalid` — src/cli.zig:228 `[rel: H3]`
- [x] `done` **M3** · commit `f26cff8` · path redaction over-matches Zig `//` and `///` comment markers as `<path>`, corrupting AI context & report excerpts — src/ai/redaction.zig:85
- [x] `done` **M4** · commit `4051f44` · doctest lineOfRef unchecked u32 accumulator panics (SIGABRT) on a malformed `--case` ref instead of CaseNotFound — src/doctest_command.zig `[rel: H1]`
- [x] `done` **M5** · commit `38ebc92` · cache.enabled / cache.directory / report.formats parsed & validated but never consumed — src/config.zig `[rel: H5]`
- [ ] `todo` **M6** · commit `—` · matcher.Mode json_unordered / regex / diagnostic unreachable from block parsing — src/doctest/block.zig
- [ ] `todo` **M7** · commit `—` · doctest --mutate under-reports: candidatesOrParseError has the 4-of-8 collector restriction → 0 mutants for Phase-2-only snippets — src/doctest/mutation_experiment.zig `[rel: H2]`
- [ ] `todo` **M8** · commit `—` · AI-context normalizeAbsolutePaths misses scheme/colon-prefixed paths (file:// URIs) → path leak — src/ai/redaction.zig
- [ ] `todo` **M9** · commit `—` · AI-context mutant.id & operator fields bypass redaction → untrusted-report paths/secrets leak verbatim — src/ai/command.zig
- [ ] `todo` **M10** · commit `—` · report.summarize per-status arithmetic unpinned; validate() blind to a score-inflating regression — src/report.zig:223-235 `[rel: H4]`
- [ ] `todo` **M11** · commit `—` · JUnit XML renderer emits XML-illegal control chars (e.g. ANSI ESC) → invalid XML — src/report_junit.zig
- [ ] `todo` **M12** · commit `—` · validate_pipeline_artifact_tree silently skips all committed verification/report.json artifacts — scripts/validate_task_system.py `[rel: H4]`

## Low
- [ ] `todo` **L1** · commit `—` · AI explain/suggest returns wrong error code (REPORT_NOT_FOUND) for an existing report with an invalid empty-commands mutant — src/ai/command.zig
- [ ] `todo` **L2** · commit `—` · integration dangling-original regression guard is inert (ArenaAllocator never frees/poisons source) — test/integration_run_test.zig:41-115
- [ ] `todo` **L3** · commit `—` · property_report top-of-funnel structural guards have no negative fixture/unit test — src/property/report.zig
- [ ] `todo` **L4** · commit `—` · commandSpecsForConfigured re-parses configured commands once per surviving mutant — src/run_command.zig
- [ ] `todo` **L5** · commit `—` · commandSpecsForSelection called O(M) times per file instead of O(1) — src/run_command.zig
- [ ] `todo` **L6** · commit `—` · error-path/optional skip-guards use exact byte-string equality → no-op (equivalent) mutants — src/mutators/error_path.zig:99-101 `[rel: H2]`
- [ ] `todo` **L7** · commit `—` · per-mutant workspace walker descends into excluded .git/.zig-cache/zig-out dirs — src/cli.zig:228-256 `[rel: H3]`
- [ ] `todo` **L8** · commit `—` · per-run workspace base dir ({run_id}/workspaces) never deleted → stale dir leaked every run — src/cli.zig `[rel: H3]`
- [ ] `todo` **L9** · commit `—` · partial per-mutant workspace orphaned (cleanup_failures undercounted) when setupWorkspace fails — src/cli.zig `[rel: H3]`
- [ ] `todo` **L10** · commit `—` · documented per-worker cache/output isolation unenforced: worker_pool.cacheDirIn/outDirIn are dead — src/worker_pool.zig
- [ ] `todo` **L11** · commit `—` · matchGlob silently treats >64-segment paths as non-matching → drops deeply nested source files — src/cli.zig (glob matcher)
- [ ] `todo` **L12** · commit `—` · doctest per-case workspace-creation failure aborts the whole run (exit 4) instead of isolating the case — src/doctest/runner.zig
- [ ] `todo` **L13** · commit `—` · entire src/property/ subsystem is production-unreferenced (test-only) — src/property/
- [ ] `todo` **L14** · commit `—` · dead `future_global_options` array never read — src/root.zig
- [ ] `todo` **L15** · commit `—` · report.writeJson is a dead public export with no callers — src/report.zig
- [ ] `todo` **L16** · commit `—` · triplicated AI option-parsing loops across runAiCommand/runDoctestAi/runDoctestSurvivorAi — src/ai/
- [ ] `todo` **L17** · commit `—` · emitCleanupWarningIfNeeded silently ignores its arena allocator parameter — src/cli.zig
- [ ] `todo` **L18** · commit `—` · sourceFor performs an O(M*F) linear scan, once per mutant candidate — src/run_command.zig
- [ ] `todo` **L19** · commit `—` · findBlockByLine O(B) linear scan called per block ref in the hot doctest cache-key loop — src/doctest/
- [ ] `todo` **L20** · commit `—` · doctest --no-color parsed and stored but never threaded to any renderer — src/doctest_command.zig
- [ ] `todo` **L21** · commit `—` · `zentinel init --test-command` writes raw user input into TOML without escaping quotes (structure injection) — src/cli.zig
- [ ] `todo` **L22** · commit `—` · `--mutate` anywhere in doctest args hijacks dispatch, preempting named AI subcommands — src/doctest_command.zig
- [ ] `todo` **L23** · commit `—` · boolean_literal mutates enum field declarations named `true`/`false` → guaranteed compile_error — src/mutators/boolean.zig `[rel: H2]`
- [ ] `todo` **L24** · commit `—` · doctest mutator-spec validator (validateDoc) falsely flags every stable Phase-2 operator as drift — src/doctest/ `[rel: H2]`
- [ ] `todo` **L25** · commit `—` · documented experimental-backend diagnostics artifact never written; diagnosticsToJson is a dead export — src/zir_backend.zig, src/air_backend.zig
- [ ] `todo` **L26** · commit `—` · CLI experimental-backend diagnostic rendering (runListMutants stderr note) has no direct test — src/list_mutants_command.zig
- [ ] `todo` **L27** · commit `—` · mode_matrix non-primary columns bypass Phase B.5 configured-suite re-verification → unsound per-mode `survived` — src/run_command.zig `[rel: H5]`
- [ ] `todo` **L28** · commit `—` · report.normalizeExcerpt leaves machine-absolute paths after `:` / `=` / `>` verbatim → leak + non-determinism — src/report.zig
- [ ] `todo` **L29** · commit `—` · AI-context test_context.selection_reason bypasses redaction → paths/secrets leak — src/ai/context.zig
- [ ] `todo` **L30** · commit `—` · each source file AST-parsed twice per run (generateCandidates and selectionForFile) — src/run_command.zig
- [ ] `todo` **L31** · commit `—` · run/list-mutants `--operator` accepts unknown names → silently 0 mutants, clean exit 0 — src/cli.zig
- [ ] `todo` **L32** · commit `—` · doctest AI subcommands accept a missing required positional arg → opaque AI error instead of usage error — src/ai/doctest_command.zig
- [ ] `todo` **L33** · commit `—` · ci.sh advisory_dogfood suppresses all diagnostic output and always blames survivors despite infra-only failures — scripts/ci.sh
- [ ] `todo` **L34** · commit `—` · release_acceptance.py check_criteria uses execute_checks=False → false-OK when a verified_by script fails — scripts/release_acceptance.py
- [ ] `todo` **L35** · commit `—` · MUTATOR_SPEC Operator Overlap policy (restrict contexts) contradicts code's emit-from-both/dedup (doc-vs-code) — docs/MUTATOR_SPEC.md
- [ ] `todo` **L36** · commit `—` · MUTATOR_SPEC Operator Overlap omits the loop_boundary/comparison_boundary while-condition precedence rule (doc) — docs/MUTATOR_SPEC.md
- [ ] `todo` **L37** · commit `—` · in-tree TOML parser silently accepts duplicate keys (first value wins) — src/config_toml.zig
- [ ] `todo` **L38** · commit `—` · property_report failed_without_shrink branch / 'unsupported' shrink status untested — src/property/report.zig
- [ ] `todo` **L39** · commit `—` · Generator.intRange (and boolean/bytes) untested dead public API; intRange has a latent overflow/panic — src/property/generator.zig
- [ ] `todo` **L40** · commit `—` · mutator killed/survivor fixtures assert only candidate emission, never the kill/survive outcome — test/
- [ ] `todo` **L41** · commit `—` · duplicate ISO-8601 timestamp logic in cli.zig (buildObservation does not reuse isoTimestamp) — src/cli.zig
- [ ] `todo` **L42** · commit `—` · isQuotedMeta is a trivially thin wrapper that always equals isMeta — src/command.zig
- [ ] `todo` **L43** · commit `—` · ai.source_context_lines parsed & validated but never passed to the AI context builder — src/config.zig, src/ai/context.zig `[rel: H5]`
- [ ] `todo` **L44** · commit `—` · `--verbose` and `--quiet` accepted together on `run`; quiet silently wins — src/cli.zig
- [ ] `todo` **L45** · commit `—` · zig.modes = [] accepted by config validation but silently overrides user intent — src/config.zig `[rel: H5]`
- [ ] `todo` **L46** · commit `—` · benchmark.sh emits a committed static fixture, not live benchmark measurements — scripts/benchmark.sh
- [ ] `todo` **L47** · commit `—` · release_acceptance.py reads release_evidence.json without an is_file() guard → uncaught FileNotFoundError — scripts/release_acceptance.py
- [ ] `todo` **L48** · commit `—` · resolve_zig_import 'src/' prefix branch is unreachable dead code — src/zig_version.zig
- [ ] `todo` **L49** · commit `—` · validate_failure_recovery self-test silently skips non-dict invalid fixtures — scripts/validate_task_system.py
- [ ] `info` **L50** · commit `—` · closed-findings audit: prior CODEX/FU behavioral bugs confirmed FIXED in code — INFORMATIONAL, nothing to fix (close immediately)

## Suspected — triage (fix the real ones; `refuted` + one-line reason for the rest)
- [ ] `todo` **S1** · commit `—` · doctest survivor AI context leaks operator/survivor_ref/case_id/mutant_id unredacted — src/ai/doctest_command.zig
- [ ] `todo` **S2** · commit `—` · property_report rejection loop asserts only `v != .ok`, never the intended violation tag — src/property/report.zig
- [ ] `todo` **S3** · commit `—` · SHA-256 of each source file recomputed once per mutant in the Phase C hot loop — src/run_command.zig
- [ ] `todo` **S4** · commit `—` · build.zig silent zero-test build when test/ is inaccessible (catch return swallows openDir error) — build.zig
- [ ] `todo` **S5** · commit `—` · release_dogfood_gate.py self_test()/main() crash with unhandled JSONDecodeError on a malformed manifest — scripts/release_dogfood_gate.py
- [ ] `todo` **S6** · commit `—` · MUTATOR_SPEC documents error_catch_unreachable as 'compiles' but code emits 'may_fail' (doc-vs-code) — docs/MUTATOR_SPEC.md `[rel: M1]`
- [ ] `todo` **S7** · commit `—` · sole e2e kill/survive test binds only fungible aggregate counts; an add↔mul classification swap passes CI — test/ `[rel: H4]`
- [ ] `todo` **S8** · commit `—` · cli.zig is a 1431-line god-file spanning six distinct concerns — src/cli.zig
- [ ] `todo` **S9** · commit `—` · cli.zig private config_path duplicates root.zig's exported config_default_path — src/cli.zig
- [ ] `todo` **S10** · commit `—` · enabled() called once per candidate → O(M*E) post-collection operator filter — src/run_command.zig
- [ ] `todo` **S11** · commit `—` · matchModeFor silently treats 'text output subset' as exact matching — src/doctest/
- [ ] `todo` **S12** · commit `—` · TOML parser does not process backslash escape sequences in double-quoted strings — src/config_toml.zig
- [ ] `todo` **S13** · commit `—` · validate_task_system: empty allowed_files=[] / forbidden_files=[] pass via Python all() vacuous truth — scripts/validate_task_system.py
- [ ] `todo` **S14** · commit `—` · completion_evidence files_changed/tests_added/tests_run/follow_up_tasks accept empty lists via vacuous all() — scripts/validate_task_system.py
- [ ] `todo` **S15** · commit `—` · no doc states which commands require the external `zig` binary — docs/
- [ ] `todo` **S16** · commit `—` · MUTATION_GATE_POLICY.md retry table omits the 'Architecture' task class (diverges from FAILURE_RECOVERY.md) — docs/MUTATION_GATE_POLICY.md
- [ ] `todo` **S17** · commit `—` · third verbatim copy of the unchecked-u32 lineOfRef accumulator overflow — src/doctest/mutator_doctest.zig `[rel: M4]`
