# Handoff Contracts

Every pipeline step emits a structured handoff artifact. Handoffs prevent context drift and allow fresh agents to continue work without implicit memory.

Pre-`041` handoffs are recorded in the active task's `tasks/STATUS.md` completion log entry and the matching `tasks/status.json` `completion_evidence` entry. Chat history is never the durable handoff.

## Canonical JSON Handoff

The JSON handoff is the canonical machine-readable artifact. Markdown handoffs are optional summaries and must not be the only durable handoff after task `041` is complete.

```json
{
  "schema_version": "zentinel.pipeline.handoff.v1",
  "task_id": "043",
  "role": "Mutation Agent",
  "status": "passed",
  "files_changed": [],
  "tests_added": [],
  "commands_executed": [
    {
      "command": "zentinel run --operator comparison_boundary",
      "status": "passed"
    }
  ],
  "artifacts_produced": [
    "artifacts/pipeline/043/mutation/report.json"
  ],
  "known_risks": [],
  "assumptions": [],
  "mutation_results": {
    "killed": 12,
    "survived": 0,
    "invalid": 0
  },
  "property_results": null,
  "doctest_results": null,
  "next_step_instructions": "Proceed to final verifier."
}
```

## Optional Markdown Summary

```md
## Step Result
Task:
Role:
Status:
Files changed:
Tests added:
Commands executed:
Artifacts produced:
Known risks:
Assumptions:
Mutation results:
Property results:
Doctest results:
Next-step instructions:
```

Required fields:

- Task
- Role
- Status
- Files changed
- Commands executed
- Artifacts produced
- Known risks
- Assumptions
- Next-step instructions

Optional fields become required when applicable:

- Tests added
- Mutation results
- Property results
- Doctest results

## JSON Field Contract

| Field | Type | Required | Rule |
| --- | --- | --- | --- |
| `schema_version` | string | yes | Must be `zentinel.pipeline.handoff.v1`. |
| `task_id` | string | yes | Three-digit task id. |
| `role` | string | yes | One role from `docs/AGENT_ROLE_SPEC.md`. |
| `status` | string | yes | `passed`, `failed`, `blocked`, `needs_review`, or `not_applicable`. |
| `files_changed` | array string | yes | Project-relative paths only. |
| `tests_added` | array string | yes | tests_added is cumulative task-level evidence: list every approved test, fixture, doctest, or property case added for the task so far. A role that adds no tests keeps the cumulative list unchanged and records role-local test changes in `commands_executed`, role-specific result fields, or `known_risks`. |
| `commands_executed` | array object | yes | Include failed commands and skipped required commands with reasons. |
| `artifacts_produced` | array string | yes | Project-relative artifact paths. |
| `known_risks` | array string | yes | Use empty array only when no residual risk is known. |
| `assumptions` | array string | yes | Explicit assumptions; do not hide product choices here. |
| `mutation_results` | object or null | conditional | Required for Mutation Agent and Mutation Triage Agent. |
| `property_results` | object or null | conditional | Required when property tests are required. |
| `doctest_results` | object or null | conditional | Required when public examples or doctest code changed. |
| `next_step_instructions` | string | yes | Must name the next role or escalation outcome. |

Command object:

```json
{
  "command": "zig build test --summary all",
  "status": "failed",
  "exit_code": 1,
  "summary": "config rejects unknown backend failed before validation existed"
}
```

Do not include full logs unless the log is itself the artifact being handed off.

## Formatting Rules

- Use project-relative paths.
- Do not include absolute temp paths.
- Do not omit failed commands.
- Keep assumptions explicit.
- Link artifacts by path, not pasted bulk content.
- Summaries must distinguish evidence from inference.

## Handoff Validation

A handoff is invalid when:

- required fields are absent
- a failed command is omitted
- files changed are incomplete
- risks are hidden
- mutation survivors are summarized without detailed artifact reference
- next-step instructions conflict with task scope

## Step-Specific Requirements

| Role | Additional required handoff content |
| --- | --- |
| Orchestrator | Role route selected, skipped-role reasons, and current task/control-file evidence. |
| Phase Planner | Phase boundary, prerequisite ordering, and task split rationale. |
| Task Queue Manager Start | Active task transition evidence and synchronized queue/status files. |
| Planner | Referenced contracts, allowed/forbidden file review, and implementation risk notes. |
| Test Author | Failing command evidence and acceptance criteria covered. |
| Test Reviewer | Approved test list or required changes. |
| Implementer | Targeted passing command evidence and changed files. |
| Implementation Reviewer | Forbidden-file check and architecture drift assessment. |
| Mutation Agent | Mutation report path, baseline evidence, survivor and invalid counts. |
| Mutation Triage Agent | Classification for every survivor and retry/escalation recommendation. |
| Property Test Agent | Invariants, seeds, generated case count, minimized failure if any. |
| Doctest Agent | Changed docs, case IDs, snapshot diff summary. |
| Architecture Reviewer | Public contract drift, ADR need, and invariant/style citations. |
| Verifier | Final ordered command list, skipped stage reasons, completion recommendation. |
| Task Queue Manager Complete | Completion evidence, final task-state synchronization, and next-task handoff. |

## Machine-Readable Naming

Use deterministic file names:

```text
artifacts/pipeline/<task-id>/handoffs/00-orchestrator.json
artifacts/pipeline/<task-id>/handoffs/01-phase-planner.json
artifacts/pipeline/<task-id>/handoffs/02-task-queue-manager-start.json
artifacts/pipeline/<task-id>/handoffs/03-planner.json
artifacts/pipeline/<task-id>/handoffs/04-test-author.json
artifacts/pipeline/<task-id>/handoffs/05-test-reviewer.json
artifacts/pipeline/<task-id>/handoffs/06-implementer.json
artifacts/pipeline/<task-id>/handoffs/07-implementation-reviewer.json
artifacts/pipeline/<task-id>/handoffs/08-mutation-agent.json
artifacts/pipeline/<task-id>/handoffs/09-mutation-triage-agent.json
artifacts/pipeline/<task-id>/handoffs/10-property-test-agent.json
artifacts/pipeline/<task-id>/handoffs/11-doctest-agent.json
artifacts/pipeline/<task-id>/handoffs/12-architecture-reviewer.json
artifacts/pipeline/<task-id>/handoffs/13-verifier.json
artifacts/pipeline/<task-id>/handoffs/14-task-queue-manager-complete.json
```

If a role is not required, the Verifier records the skip reason instead of creating a fake passing handoff.

Optional Markdown summaries use the same basename with `.md` only when useful for human review. The JSON file remains the authority.
