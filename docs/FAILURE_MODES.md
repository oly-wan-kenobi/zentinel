# Failure Modes

This document catalogs concrete failure modes zentinel must classify, report, or recover from. It is the counterpart to `docs/HARNESS.md`: the harness defines where evidence comes from; this file defines the named failures agents and tests should cover.

## How This Document Works

Failure modes are numbered `F-NNN`. Numbers are stable and never reused.

Each failure mode has:

- a stable number
- a name
- the phase where it occurs
- the expected zentinel outcome
- related error code or result status
- invariants stressed
- required test surface

## Catalog

**F-001. Zig executable missing**
- *Phase.* Zig version.
- *Expected outcome.* Command fails before project analysis.
- *Code/status.* `ZNTL_ZIG_NOT_FOUND`.
- *Invariants stressed.* I-006, I-014.
- *Required test surface.* Version-policy test with stubbed missing Zig.

**F-002. Unsupported Zig version**
- *Phase.* Zig version.
- *Expected outcome.* Clear diagnostic explaining latest-stable policy.
- *Code/status.* `ZNTL_ZIG_UNSUPPORTED_VERSION`.
- *Invariants stressed.* I-006.
- *Required test surface.* Version-policy test with stubbed older version.

**F-003. Config parse error**
- *Phase.* Config.
- *Expected outcome.* Config validation fails with source location when available.
- *Code/status.* `ZNTL_CONFIG_PARSE_ERROR`.
- *Invariants stressed.* I-014.
- *Required test surface.* Config parser fixture.

**F-004. Unknown or unsupported config key**
- *Phase.* Config.
- *Expected outcome.* Config validation fails without silently ignoring the key.
- *Code/status.* `ZNTL_CONFIG_UNKNOWN_KEY`.
- *Invariants stressed.* I-005, I-014.
- *Required test surface.* Config parser fixture.

**F-005. Experimental backend requested without opt-in**
- *Phase.* Config.
- *Expected outcome.* Config validation fails and AST remains default.
- *Code/status.* `ZNTL_CONFIG_EXPERIMENTAL_BACKEND`.
- *Invariants stressed.* I-005.
- *Required test surface.* Backend config test.

**F-006. Project has no eligible sources**
- *Phase.* Project model.
- *Expected outcome.* Project analysis fails before mutation generation.
- *Code/status.* `ZNTL_PROJECT_NO_SOURCES`.
- *Invariants stressed.* I-001.
- *Required test surface.* Project model fixture.

**F-007. Backend parse error**
- *Phase.* Backend.
- *Expected outcome.* Backend reports parse failure with file context and emits no mutants for that file.
- *Code/status.* `ZNTL_BACKEND_PARSE_ERROR`.
- *Invariants stressed.* I-001, I-014.
- *Required test surface.* AST backend fixture.

**F-008. Source mapping failed**
- *Phase.* Backend.
- *Expected outcome.* Candidate is rejected or reported as internal backend failure; no approximate span is emitted.
- *Code/status.* `ZNTL_BACKEND_SOURCE_MAPPING_FAILED`.
- *Invariants stressed.* I-002, I-008, I-011.
- *Required test surface.* Source-map guardrail test.

**F-009. Mutator invalid candidate**
- *Phase.* Mutator.
- *Expected outcome.* Mutant is classified as invalid or generation fails with a mutator diagnostic.
- *Code/status.* `ZNTL_MUTATOR_INVALID_CANDIDATE`, `invalid`.
- *Invariants stressed.* I-011.
- *Required test surface.* Mutator contract test.

**F-010. Sandbox creation failed**
- *Phase.* Sandbox.
- *Expected outcome.* Run stops before applying mutants.
- *Code/status.* `ZNTL_SANDBOX_CREATE_FAILED`.
- *Invariants stressed.* I-007.
- *Required test surface.* Sandbox error-path test.

**F-011. Patch original text mismatch**
- *Phase.* Sandbox.
- *Expected outcome.* Mutant is not applied and failure is reported as invalid or sandbox error.
- *Code/status.* `ZNTL_SANDBOX_PATCH_MISMATCH`.
- *Invariants stressed.* I-008, I-011.
- *Required test surface.* Patch mismatch fixture.

**F-012. Patch span out of range**
- *Phase.* Sandbox.
- *Expected outcome.* Mutant is not applied and failure is reported as invalid.
- *Code/status.* `ZNTL_SANDBOX_PATCH_OUT_OF_RANGE`, `invalid`.
- *Invariants stressed.* I-008, I-011.
- *Required test surface.* Patch bounds test.

**F-013. Baseline failed**
- *Phase.* Runner.
- *Expected outcome.* Mutation execution stops and report records baseline failure.
- *Code/status.* `ZNTL_RUNNER_BASELINE_FAILED`, run-level `baseline_failed`.
- *Invariants stressed.* I-001.
- *Required test surface.* Runner baseline-failure fixture.

**F-014. Mutant killed**
- *Phase.* Runner.
- *Expected outcome.* Mutant result is `killed`.
- *Code/status.* `killed`.
- *Invariants stressed.* I-001, I-003.
- *Required test surface.* Fixture where selected tests fail only after mutation.

**F-015. Mutant survived**
- *Phase.* Runner.
- *Expected outcome.* Mutant result is `survived`.
- *Code/status.* `survived`.
- *Invariants stressed.* I-001, I-012.
- *Required test surface.* Fixture with an intentional missing assertion.

**F-016. Mutant compile error**
- *Phase.* Runner.
- *Expected outcome.* Mutant result is `compile_error`.
- *Code/status.* `compile_error`.
- *Invariants stressed.* I-010, I-011.
- *Required test surface.* Fixture where replacement creates a Zig compile failure.

**F-017. Mutant timeout**
- *Phase.* Runner.
- *Expected outcome.* Mutant result is `timeout` with command and timeout evidence.
- *Code/status.* `ZNTL_RUNNER_TIMEOUT`, `timeout`.
- *Invariants stressed.* I-001, I-014.
- *Required test surface.* Runner timeout test with controlled command.

**F-018. Report schema violation**
- *Phase.* Report.
- *Expected outcome.* Report writing fails before emitting a public artifact or emits a clearly invalid internal diagnostic in tests.
- *Code/status.* `ZNTL_REPORT_SCHEMA_ERROR`.
- *Invariants stressed.* I-014.
- *Required test surface.* Report schema contract test.

**F-019. Cache key mismatch**
- *Phase.* Cache.
- *Expected outcome.* Cache entry is ignored or invalidated; stale result is not reused.
- *Code/status.* `ZNTL_CACHE_KEY_MISMATCH`.
- *Invariants stressed.* I-013.
- *Required test surface.* Cache key property test.

**F-020. AI disabled**
- *Phase.* AI.
- *Expected outcome.* AI command fails clearly without affecting deterministic reports.
- *Code/status.* `ZNTL_AI_DISABLED`.
- *Invariants stressed.* I-004.
- *Required test surface.* AI CLI/config test.

**F-021. AI response invalid**
- *Phase.* AI.
- *Expected outcome.* Advisory output is rejected; deterministic evidence remains unchanged.
- *Code/status.* `ZNTL_AI_RESPONSE_INVALID`.
- *Invariants stressed.* I-004, I-014.
- *Required test surface.* Stub provider malformed response test.

**F-022. Doctest block invalid**
- *Phase.* Doctest.
- *Expected outcome.* Doctest reports invalid block with line number and no AI interpretation.
- *Code/status.* `ZNTL_DOCTEST_INVALID_BLOCK`.
- *Invariants stressed.* I-016.
- *Required test surface.* Doctest block parser test.

**F-023. Doctest output mismatch**
- *Phase.* Doctest.
- *Expected outcome.* Doctest case fails with normalized expected/actual evidence.
- *Code/status.* `ZNTL_DOCTEST_SNAPSHOT_MISMATCH`.
- *Invariants stressed.* I-015, I-016.
- *Required test surface.* Doctest snapshot test.

**F-024. Task metadata invalid**
- *Phase.* Task system.
- *Expected outcome.* Validator fails and agents repair task metadata before implementation work.
- *Code/status.* `ZNTL_TASK_STATE_INVALID`.
- *Invariants stressed.* I-017, I-018, I-020.
- *Required test surface.* `scripts/validate_task_system.py` self-checks and CI invocation.

**F-025. Nondeterministic repeated report**
- *Phase.* Verification.
- *Expected outcome.* Verification fails and task returns to implementation or property-test author.
- *Code/status.* Verification failure.
- *Invariants stressed.* I-002, I-003, I-015.
- *Required test surface.* Repeat-run comparison fixture.

**F-026. AI provider not allowed**
- *Phase.* AI.
- *Expected outcome.* Advisory command fails before prompt construction and does not call the provider.
- *Code/status.* `ZNTL_AI_PROVIDER_NOT_ALLOWED`.
- *Invariants stressed.* I-004.
- *Required test surface.* AI CLI provider override test.

**F-027. Mutation AI report missing**
- *Phase.* AI.
- *Expected outcome.* Mutation advisory command that requires a deterministic report fails as a usage error.
- *Code/status.* `ZNTL_AI_REPORT_NOT_FOUND`.
- *Invariants stressed.* I-004, I-014.
- *Required test surface.* AI CLI report-path test.

**F-028. Mutation AI target missing**
- *Phase.* AI.
- *Expected outcome.* Mutation advisory command fails when the requested durable mutant ID or report-local display ID does not resolve in the selected report.
- *Code/status.* `ZNTL_AI_TARGET_NOT_FOUND`.
- *Invariants stressed.* I-003, I-004.
- *Required test surface.* AI CLI mutant-ref resolution test.

**F-029. Doctest AI report missing**
- *Phase.* Doctest AI.
- *Expected outcome.* `zentinel doctest explain` fails as a usage error when its selected deterministic doctest report is missing.
- *Code/status.* `ZNTL_AI_REPORT_NOT_FOUND`.
- *Invariants stressed.* I-004, I-014, I-016.
- *Required test surface.* Doctest AI CLI report-path test.

**F-030. Doctest case ref missing or ambiguous**
- *Phase.* Doctest AI.
- *Expected outcome.* Doctest command fails when a durable `dt_...` ID or anchor-line source ref does not resolve to exactly one case.
- *Code/status.* `ZNTL_DOCTEST_CASE_NOT_FOUND`.
- *Invariants stressed.* I-016.
- *Required test surface.* Doctest CLI and doctest AI case-ref resolution tests.

**F-031. Doctest suggestion doc path missing**
- *Phase.* Doctest AI.
- *Expected outcome.* `zentinel doctest suggest` fails before provider invocation when the target docs path is not an existing project-relative documentation file.
- *Code/status.* `ZNTL_DOCTEST_DOC_NOT_FOUND`.
- *Invariants stressed.* I-004.
- *Required test surface.* Doctest AI CLI docs-path test.

**F-032. Mutant compiler crash**
- *Phase.* Runner.
- *Expected outcome.* Mutant result is `compiler_crash` with command evidence and bounded compiler output.
- *Code/status.* `ZNTL_RUNNER_COMPILER_CRASH`, `compiler_crash`.
- *Invariants stressed.* I-001, I-021.
- *Required test surface.* Mutant runner fixture that simulates abnormal Zig compiler termination distinct from compile diagnostics.

**F-033. Allocator mutator escapes target allocator boundary**
- *Phase.* Mutator.
- *Expected outcome.* Candidate is rejected as invalid or blocked by fixture requirements before it can mutate the zentinel runner or harness allocator path.
- *Code/status.* `ZNTL_MUTATOR_INVALID_CANDIDATE`, `invalid`.
- *Invariants stressed.* I-007, I-011.
- *Required test surface.* Allocator mutator fixture proving only injected target allocator wrappers are mutated.

**F-034. Doctest survivor ref missing**
- *Phase.* Doctest AI.
- *Expected outcome.* `zentinel doctest explain-survivor` fails when the survivor ref does not resolve in the selected mutation-aware doctest report.
- *Code/status.* `ZNTL_DOCTEST_SURVIVOR_NOT_FOUND`.
- *Invariants stressed.* I-004, I-016.
- *Required test surface.* Doctest survivor AI CLI survivor-ref resolution test.

**F-035. Internal reportable tool error**
- *Phase.* Internal.
- *Expected outcome.* Report v1 emits `run.status = "internal_error"` only with closed deterministic `run.error` evidence, or fails before emitting a public report when that evidence cannot be constructed.
- *Code/status.* `ZNTL_INTERNAL_INVARIANT`, `internal_error`.
- *Invariants stressed.* I-001, I-014.
- *Required test surface.* Report schema contract test for internal-error reports.
