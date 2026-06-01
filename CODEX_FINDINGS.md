# CODEX Findings

Read-only adversarial audit captured by Codex on 2026-06-01.

## Scope

- Repository: `/Users/oli/Projects/zentinel`
- Audit stance: assume hidden correctness, determinism, task-control, testing, or agent-protocol failures until repository evidence proves otherwise.
- Changes made during audit: none before this artifact.
- Task system validator result observed during audit: `python3 scripts/validate_task_system.py` passed with `122 tasks`.
- Post-capture validator note: after creating this root-level artifact, `python3 scripts/validate_task_system.py` fails because `CODEX_FINDINGS.md` is a dirty file with no active task and is not listed in task `121` completion evidence. No task-control files were changed to force a pass.
- Task state observed during audit: no active task and no next task.

## Executive Risk Summary

The task system appears structurally valid, but task validation is not product-semantic proof. The strongest risks found are runtime and contract-boundary risks: mutation runs appear able to continue after unsupported or missing Zig discovery, sandbox workspace materialization can silently omit files, doctest commands inherit host environment, evidence truncation can split UTF-8, and mutation execution can silently drop candidates with missing source files.

The repository should be treated as safe for autonomous sequential task handling only if new work is added through the task system and the findings below are captured or resolved before trusting adversarial mutation results.

## Ranked Findings

| Rank | Severity | Confidence | Finding |
| ---: | --- | --- | --- |
| 1 | High | High | `zentinel run` appears to continue after Zig version discovery reports missing or unsupported Zig. |
| 2 | High | Medium | Sandbox workspace materialization silently ignores file copy failures. |
| 3 | Medium | High | Doctest command execution inherits the host environment. |
| 4 | Medium | High | Runner output truncation is byte-based and not UTF-8 boundary safe. |
| 5 | Medium | Medium | Mutation execution silently drops candidates whose source file cannot be found. |
| 6 | Low | High | Task Markdown contains stale handoff guidance that contradicts machine state completion. |

## Detailed Findings

### 1. `run` Does Not Fail Fast On Unsupported Zig

- Severity: High
- Confidence: High
- Governing contract: `docs/INVARIANTS.md` I-006, ADR-0007, `docs/ZIG_VERSION_POLICY.md`, and the pipeline validation step in `docs/ARCHITECTURE.md`.
- Direct evidence:
  - `src/cli.zig:358` says version validation in `run` is non-fatal.
  - `src/cli.zig:360-363` discovers Zig and only prints the status line before continuing.
  - `src/cli.zig:296-299` records `supported_zig_version` when Zig is not found.
  - `docs/ZIG_VERSION_POLICY.md:29-34` requires unsupported Zig to fail fast.
  - `docs/ZIG_VERSION_POLICY.md:61-67` says CI must fail before running tests under unsupported Zig.
- Inference / failure mode: a mutation run can produce a report under Zig `0.15`, nightly, or no discoverable Zig while still carrying apparently normal metadata. That undermines the pinned-Zig and stable-AST guarantees.
- Why existing tests or validators may not catch it: the task validator checks task metadata only. Version tests can cover `check` or `version` behavior while `run` remains warning-only.
- Minimal read-only verification: `nl -ba src/cli.zig | sed -n '296,363p'`
- Smallest safe remediation direction: make `run` fail before mutation work when Zig is missing or unsupported. Keep warning-only behavior only for commands whose contract explicitly allows it.

### 2. Sandbox Copy Failures Are Swallowed

- Severity: High
- Confidence: Medium
- Governing contract: `docs/DISCIPLINE.md` D-200, D-202, D-301; `docs/SANDBOX_SECURITY.md` workspace rules; isolated-worktree mutation in `docs/ARCHITECTURE.md`.
- Direct evidence:
  - `src/cli.zig:239-246` walks the project and copies files into a workspace.
  - `src/cli.zig:244` ignores each `copyFile` failure with `catch continue`.
  - `src/cli.zig:246-248` then writes the patched file and returns the workspace as created.
- Inference / failure mode: unreadable files, transient filesystem errors, or failed copies can create an incomplete test workspace. A mutant can then be classified from a project that is not equivalent to the real project.
- Why existing tests or validators may not catch it: happy-path sandbox tests will not simulate copy failure, and the task validator cannot inspect runtime workspace fidelity.
- Minimal read-only verification: `nl -ba src/cli.zig | sed -n '239,248p'`
- Smallest safe remediation direction: propagate copy failures into `workspace_create_failed` or another explicit internal failure with evidence.

### 3. Doctest Execution Inherits Host Environment

- Severity: Medium
- Confidence: High
- Governing contract: `docs/DISCIPLINE.md` D-403, CI/network-free expectations in `docs/TDD_POLICY.md`, and environment policy in `docs/SANDBOX_SECURITY.md`.
- Direct evidence:
  - `src/cli.zig:595-607` executes doctest commands through `std.process.run`.
  - `src/cli.zig:605` sets `.environ_map = null`, which inherits the host environment.
- Inference / failure mode: executable docs can become dependent on local env vars, PATH shape, credentials, locale, or CI-specific state. If doctest output is later used in reports or AI context, host-specific data may leak.
- Why existing tests or validators may not catch it: deterministic sample commands can pass while adversarial or environment-dependent doctests remain untested.
- Minimal read-only verification: `nl -ba src/cli.zig | sed -n '595,607p'`
- Smallest safe remediation direction: pass the same minimal environment policy used by the runner, or document and test a narrower doctest-specific environment contract.

### 4. Runner Excerpt Truncation Can Split UTF-8

- Severity: Medium
- Confidence: High
- Governing contract: `docs/SCHEMA_REGISTRY.md` requires safe-character-boundary truncation; `docs/REPORT_FORMAT.md` specifies bounded evidence excerpts.
- Direct evidence:
  - `src/runner.zig:89-93` normalizes output and slices `normalized[0..len]`.
  - `docs/SCHEMA_REGISTRY.md:36` says output excerpts must truncate on a safe character boundary before schema validation.
- Inference / failure mode: command output with a multibyte character crossing byte 4096 can produce invalid UTF-8 in report evidence or schema-facing data.
- Why existing tests or validators may not catch it: length-oriented ASCII tests pass while multibyte boundary failures remain uncovered.
- Minimal read-only verification: inspect `src/runner.zig:89-93` and compare it with the AI context capping helper.
- Smallest safe remediation direction: share one safe UTF-8 truncation helper for runner, report, and AI excerpts.

### 5. Missing Candidate Source Is Silently Ignored

- Severity: Medium
- Confidence: Medium
- Governing contract: `docs/INVARIANTS.md` I-011 and I-012; mutation correctness rules in `docs/DISCIPLINE.md`; internal failure discipline in `docs/DISCIPLINE.md`.
- Direct evidence:
  - `src/run_command.zig:254-258` looks up the candidate file and uses `orelse continue` when it cannot be found.
- Inference / failure mode: if a backend, mutator, or filter emits a candidate with a path mismatch, zentinel underreports mutants instead of surfacing an internal contract violation.
- Why existing tests or validators may not catch it: normal AST collectors use discovered file paths, so tests built only through the normal path will not exercise backend/path drift.
- Minimal read-only verification: `nl -ba src/run_command.zig | sed -n '250,260p'`
- Smallest safe remediation direction: turn this into an explicit invalid/internal diagnostic rather than silently continuing.

### 6. Stale Task Handoff Prose Can Mislead Agents

- Severity: Low
- Confidence: High
- Governing contract: `docs/INVARIANTS.md` I-018, ADR-0004, and synchronization rules in `docs/AUTONOMOUS_AGENT_PROTOCOL.md`.
- Direct evidence:
  - `tasks/STATUS.md:9-10` says active and next task are both `none`.
  - `tasks/STATUS.md:151` says the next agent should start task `000`.
  - `tasks/QUEUE.md:61` marks task `000` complete.
- Inference / failure mode: an autonomous agent that trusts stale prose over machine state could restart completed work or create an unnecessary lifecycle transition.
- Why existing tests or validators may not catch it: `python3 scripts/validate_task_system.py` passed, so the validator likely validates structured fields rather than stale natural-language handoff instructions.
- Minimal read-only verification: `python3 scripts/validate_task_system.py && nl -ba tasks/STATUS.md | sed -n '5,16p;147,152p'`
- Smallest safe remediation direction: remove stale handoff prose or extend validation to reject handoff text that names a completed next task.

## Cross-Cutting Systemic Risks

- Product-semantic guarantees rely on runtime checks that are not all enforced by the task validator.
- Stable AST behavior can still be compromised by unsupported Zig runtime behavior.
- Sandbox correctness depends on workspace fidelity, but the current materialization path can suppress copy failures.
- Environment determinism is strong in the mutation runner path but weaker in doctest execution.
- Report/schema correctness can diverge where separate truncation helpers implement different byte and character-boundary behavior.

## Test And Validator Blind Spots

- No observed validator coverage for runtime Zig enforcement in `zentinel run`.
- No observed adversarial filesystem-copy failure coverage for sandbox workspace setup.
- Output-bound tests should include multibyte UTF-8 at the exact truncation boundary.
- Doctest execution needs an environment-leak regression test.
- Backend/path contract tests should include an impossible candidate file and require an explicit diagnostic.

## Unknowns Needing Further Investigation

- Whether CI has an external wrapper that blocks unsupported Zig before `zentinel run`.
- Whether doctest inheritance was intentionally scoped outside sandbox policy.
- Whether report JSON serialization rejects invalid UTF-8 later, masking runner truncation failures.
- Whether copy failures are practically reachable on supported platforms with normal project permissions.
- Whether read-side symlink containment for config, input-report, doctest fixtures, and AI context reads has complete coverage.

## Suggested Follow-Up Audits

### Audit 1: Runtime Determinism And Environment Boundary Audit

Inspect every path that executes subprocesses or reads process environment. Confirm that command argv parsing, cwd, environment, timeouts, output bounds, and classification are deterministic and match `docs/SANDBOX_SECURITY.md`, `docs/DISCIPLINE.md`, and `docs/TDD_POLICY.md`. Prioritize doctests, AI commands, baseline commands, generated preflight commands, and re-verification commands.

### Audit 2: Filesystem, Path Traversal, And Symlink Safety Audit

Inspect all read and write paths for root containment, symlink traversal, TOCTOU races, swallowed filesystem errors, cleanup behavior, and workspace isolation. Prioritize `--config`, `--input-report`, report/cache output paths, doctest fixture materialization, sandbox workspace copying, and cleanup.

### Audit 3: Mutation Correctness And Stable-AST Contract Audit

Trace candidate generation through filtering, ID assignment, sandbox patching, command execution, classification, report emission, and cache key construction. Confirm that no candidate can be silently dropped, misidentified, reordered nondeterministically, classified from incomplete evidence, or affected by AI output, ZIR/AIR paths, unsupported Zig, or non-AST backend behavior.
