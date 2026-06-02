# Deep Review — Fix Ledger

Remediation tracker for the findings in [DEEP_REVIEW.md](DEEP_REVIEW.md): **67 confirmed + 17 suspected = 84 items**.

## How to use (with `/loop`)
- **Pick rule:** the FIRST item below whose status is `todo`, read top-to-bottom (High → Medium → Low → Suspected). High is in true priority order; M/L/S are numeric.
- **Statuses:** `todo` · `wip` · `done` · `refuted` (suspected non-bugs, with a reason) · `info` (nothing to fix).
- **Definition of done (per item):** behavior fixed → a regression test that *fails pre-fix and passes post-fix* (assert the specific bucket/mutant/output bytes, never aggregate counts) → `zig build` + full `zig test` green via the zigars MCP → committed with the finding id → this row updated to `done` + short commit hash.
- Read the finding's full Evidence / Tool confirmation / Why / Repro / Suggested-fix in DEEP_REVIEW.md before touching code. Absolute paths there map to repo-relative.
- `[rel: Hx]` = closely related to that High finding; fix together when cheap.

**Progress:** 37/67 confirmed fixed · 0/17 suspected resolved  _(update this line as you go)_

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
- [x] `done` **M6** · commit `1e10ca3` · matcher.Mode json_unordered / regex / diagnostic unreachable from block parsing — src/doctest/block.zig
- [x] `done` **M7** · commit `9dae1c6` · doctest --mutate under-reports: candidatesOrParseError has the 4-of-8 collector restriction → 0 mutants for Phase-2-only snippets — src/doctest/mutation_experiment.zig `[rel: H2]`
- [x] `done` **M8** · commit `5d37c67` · AI-context normalizeAbsolutePaths misses scheme/colon-prefixed paths (file:// URIs) → path leak — src/ai/redaction.zig
- [x] `done` **M9** · commit `f26d1e8` · AI-context mutant.id & operator fields bypass redaction → untrusted-report paths/secrets leak verbatim — src/ai/command.zig
- [x] `done` **M10** · commit `81e2aea` · report.summarize per-status arithmetic unpinned; validate() blind to a score-inflating regression — src/report.zig:223-235 `[rel: H4]`
- [x] `done` **M11** · commit `abf52ca` · JUnit XML renderer emits XML-illegal control chars (e.g. ANSI ESC) → invalid XML — src/report_junit.zig
- [x] `done` **M12** · commit `c26d716` · validate_pipeline_artifact_tree silently skips all committed verification/report.json artifacts — scripts/validate_task_system.py `[rel: H4]`

## Low
- [x] `done` **L1** · commit `87de09c` · AI explain/suggest returns wrong error code (REPORT_NOT_FOUND) for an existing report with an invalid empty-commands mutant — src/ai/command.zig
- [x] `done` **L2** · commit `a1856fe` · integration dangling-original regression guard is inert (ArenaAllocator never frees/poisons source) — test/integration_run_test.zig:41-115
- [x] `done` **L3** · commit `863a325` · property_report top-of-funnel structural guards have no negative fixture/unit test — src/property/report.zig
- [x] `done` **L4** · commit `ebd7fbb` · commandSpecsForConfigured re-parses configured commands once per surviving mutant — src/run_command.zig
- [x] `done` **L5** · commit `7751f57` · commandSpecsForSelection called O(M) times per file instead of O(1) — src/run_command.zig
- [x] `done` **L6** · commit `9c71760` · error-path/optional skip-guards use exact byte-string equality → no-op (equivalent) mutants — src/mutators/error_path.zig:99-101 `[rel: H2]`
- [x] `done` **L7** · commit `381f857` · per-mutant workspace walker descends into excluded .git/.zig-cache/zig-out dirs — src/cli.zig:228-256 `[rel: H3]` — subsumed by H3: setupWorkspace routes through worker_pool.copyProjectTree (walkSelectively, never enter()s excluded dirs); proven by the "never descends into .zig-cache/zig-out/.git" test (excludeNothing copy filter → only no-descent keeps the excluded subtrees out)
- [x] `done` **L8** · commit `a9ba73d` · per-run workspace base dir ({run_id}/workspaces) never deleted → stale dir leaked every run — src/cli.zig `[rel: H3]` — runRun now best-effort deleteTrees worker_pool.workspaceRunBase(run_id) after the run (counted in cleanup_failures); workspaceRoot rebuilt as {base}/{m_id}. Red: integration test saw leaked run_19e876a19ad; green post-fix
- [x] `done` **L9** · commit `a2b7788` · partial per-mutant workspace orphaned (cleanup_failures undercounted) when setupWorkspace fails — src/cli.zig `[rel: H3]` — extracted worker_pool.createMutantWorkspace with a failure-path errdefer that deleteTrees the partial dir (bumps cleanup_failures only if removal fails); cli.setupWorkspace is now a thin wrapper. Red: orphan dir survived a forced mid-setup failure; green post-fix
- [x] `done` **L10** · commit `e194ae0` · documented per-worker cache/output isolation unenforced: worker_pool.cacheDirIn/outDirIn are dead — src/worker_pool.zig — runner.minimalEnviron now overrides ZIG_LOCAL_CACHE_DIR=cacheDirIn(".")="./.zig-cache" (cwd-relative), so each worker's own workspace owns its cache regardless of host env; cacheDirIn is now a live production caller. zig-out is inherently cwd-isolated (no override needed). Red: host /tmp/shared-zig-cache forwarded verbatim; green post-fix
- [x] `done` **L11** · commit `b954a36` · matchGlob silently treats >64-segment paths as non-matching → drops deeply nested source files — src/project_model.zig (glob matcher) — rewrote matchSegments to recurse over the raw '/'-segmented strings (no [64] buffer), preserving exact `*`/`**` semantics with zero allocation and unchanged signatures. Red: 72-segment path returned false; green post-fix
- [x] `done` **L12** · commit `54e8aea` · doctest per-case workspace-creation failure aborts the whole run (exit 4) instead of isolating the case — src/doctest/runner.zig — runZig now catches WorkspaceCreateFailed → per-case `.invalid` + ZNTL_DOCTEST_WORKSPACE_FAILED diagnostic (symmetric with the mutation path); RunError narrowed to drop it, dead cli exit-4 prong removed. Red: error escaped runCase; green post-fix
- [x] `done` **L13** · commit `6e31ceb` · entire src/property/ subsystem is production-unreferenced (test-only) — src/property/ — no-new-surface resolution (option b): corrected the docstring to state it has no runtime consumer (gated out of band) and made the sole test guard load-bearing — pinned every invalid fixture to its exact Violation + added specific-tag tests for the 4 untested branches (not_object/bad_property/bad_property_name/failed_without_shrink). Red: a not_object→ok regression the old suite missed now fails
- [x] `done` **L14** · commit `878176a` · dead `future_global_options` array never read — src/root.zig — deleted the unreferenced array + the comment that cited it; behavior-preserving (build+tests green). Pinned the one untested entry: `--quiet` → route passthrough + dispatch cli_invalid_option (detail "--quiet"). Red: making dispatch accept --quiet failed the new guard
- [x] `done` **L15** · commit `5cdfbcb` · report.writeJson is a dead public export with no callers — src/report.zig — deleted the unused writer-streaming serializer (CLI writes a buffer via writeFile, no streaming sink); toJson is now the sole serializer. Its exact canonical format stays guarded by existing byte-level golden snapshots (report_schema_test minimal_snapshot + run_command_test/*.json) — verified load-bearing: an indent_4 regression fails all four goldens
- [x] `done` **L16** · commit `2596248` · triplicated AI option-parsing loops across runAiCommand/runDoctestAi/runDoctestSurvivorAi — src/ai/ — extracted ai.command.parseSharedOption + SharedOptions (one parser for --ai-provider/--input-report/--format, error strings owned once); all three cli loops call it and keep only their own positional/--file/unknown-option logic. Behavior preserved. Red: dropping quotes from the --format error fails the new unit test (guards all three at once)
- [x] `done` **L17** · commit `26eaad8` · emitCleanupWarningIfNeeded silently ignores its arena allocator parameter — src/root.zig — dropped the unused `arena` param (false dependency) and extracted a shared `cleanup_warning_fmt` constant so emit (streams) and cleanupWarningText (allocs) use one source; updated both call sites. Red: changing the constant fails both pinned-text assertions together. (Delegating instead leaked — caught by the test allocator.)
- [x] `done` **L18** · commit `be6803c` · sourceFor performs an O(M*F) linear scan, once per mutant candidate — src/run_command.zig — replaced the per-mutant linear scan with a StringHashMap(path→source) built once before the Phase A loop (buildSourceIndex); per-candidate lookup is now O(1). Deleted dead sourceFor. Red: building the index inside the loop makes source_index_builds == 2 (per-mutant), failing the once-per-run assertion
- [x] `done` **L19** · commit `e26a729` · findBlockByLine O(B) linear scan called per block ref in the hot doctest cache-key loop — src/doctest/cache.zig — built an AutoHashMap(line_start→Block) once in buildMetadata (buildBlockIndex) and replaced the two per-ref scans with O(1) gets; deleted cache.zig's findBlockByLine. Red: building the index inside the case loop makes block_index_builds == 4, failing the once-per-document assertion
- [x] `done` **L20** · commit `02a79a1` · doctest --no-color parsed and stored but never threaded to any renderer — src/doctest_command.zig — no renderer emits ANSI color anywhere, so threading it would just be an unused param (L17 smell); removed the dead no_color field and accept --no-color as an explicit no-op (matching root.zig's global handling). Flag stays accepted; output unchanged. Red: dropping the accept branch makes parseArgs reject --no-color as UnknownOption
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
