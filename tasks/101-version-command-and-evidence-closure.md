# 101 Version Command and Evidence Closure

Sequential guard: start this task only after task `100` is complete in `tasks/STATUS.md`. Task `000` is blocked until this prerequisite closes the version-command ownership ambiguity and pre-pipeline evidence wording drift found during the latest deep repository analysis.

## Goal

Clarify the `zentinel version` Zig-discovery contract, strengthen task `005` ownership, add pre-`063` TDD evidence conventions, and remove duplicated post-`041` activation wording before project bootstrap starts.

## Scope

- Clarify that task `001` owns only policy-label `zentinel version` output.
- Clarify that task `005` adds real Zig discovery to both `zentinel version` and `zentinel check`.
- Distinguish missing-Zig diagnostics for commands that require Zig from non-fatal `zentinel version` status output.
- Add pre-`063` structured TDD evidence wording so early agents record failing command, failing output excerpt, implementation ordering, and passing command evidence.
- Add validator guardrails for the clarified task `005` and TDD evidence contracts.
- Deduplicate the post-`041` activation-order wording in pipeline artifacts docs.
- Keep Zig `0.16.0`, AST default behavior, ZIR/AIR experimental status, deterministic core behavior, and Codex-only agent contracts unchanged.

## Files allowed to modify

- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `tasks/000-project-bootstrap.md`
- `tasks/005-version-policy.md`
- `tasks/101-version-command-and-evidence-closure.md`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `docs/CLI_SPEC.md`
- `docs/FAILURE_MODES.md`
- `docs/PIPELINE_ARTIFACTS.md`
- `docs/TDD_POLICY.md`
- `scripts/validate_task_system.py`

## Files forbidden to modify

- `src/**`
- `build.zig`
- `build.zig.zon`
- `test/**/*.zig`
- `schemas/**`
- `.claude/**`

## Required tests

- First add a failing structural validator guardrail set for:
  - task `005` owning `zentinel version` missing-Zig and unsupported-Zig behavior
  - `zentinel check` retaining fatal missing-Zig and unsupported-Zig diagnostics
  - pre-`063` completion evidence naming failing command, failing output excerpt, implementation-after-failure assertion, and passing command
  - a single canonical post-`041` activation-order sentence in `docs/PIPELINE_ARTIFACTS.md`
- Run `python3 scripts/validate_task_system.py` after adding the guardrails and record the expected failures before fixing contracts.
- Run `python3 -m py_compile scripts/validate_task_system.py`.
- Run `python3 scripts/validate_task_system.py` while task `101` remains active.
- Run `jq empty tasks/status.json tasks/queue.json`.
- Run `git diff --check`.

## Acceptance criteria

- `docs/CLI_SPEC.md` unambiguously separates task `001` policy-label output from task `005` Zig discovery behavior.
- `tasks/005-version-policy.md` requires tests for `zentinel version` with supported Zig, missing Zig, and unsupported Zig, plus `zentinel check` fatal missing/unsupported Zig behavior.
- `docs/FAILURE_MODES.md` scopes `F-001` as fatal only for commands that require Zig and non-fatal status evidence for `zentinel version`.
- `docs/TDD_POLICY.md`, `docs/AGENT_GUIDE.md`, and `docs/AUTONOMOUS_AGENT_PROTOCOL.md` define the pre-`063` structured chronology evidence convention without claiming mechanical proof before task `063`.
- `docs/PIPELINE_ARTIFACTS.md` has one canonical post-`041` activation-order sentence.
- Validator guardrails cover the new contracts.
- `tasks/STATUS.md` records completion, files changed, and tests run.

## Non-goals

- Implementing CLI behavior.
- Changing Zig version policy.
- Adding source, test, schema, or build files.
- Creating pipeline artifacts before task `041`.

## Suggested implementation approach

1. Add validator checks that fail on the current ambiguous wording.
2. Update CLI, failure-mode, TDD, agent, and pipeline wording to satisfy the guardrails.
3. Update task `005` required tests and acceptance criteria.
4. Keep the final status entry explicit about this being a contract-hardening prerequisite before task `000`.

## Dogfooding implications

No runtime behavior exists yet. This task removes ambiguity before dogfoodable behavior exists so future agents can implement version discovery and TDD evidence without human coordination.

## Follow-up tasks

- `tasks/000-project-bootstrap.md`
