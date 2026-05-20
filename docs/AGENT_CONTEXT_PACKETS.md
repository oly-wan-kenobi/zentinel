# Agent Context Packets

Context packets are the only required input for fresh stateless subagents.

## Packet Contents

```json
{
  "schema_version": "zentinel.pipeline.context.v1",
  "packet_id": "043-mutation-agent-001",
  "created_from_queue_revision": "working-tree",
  "task": {
    "id": "043",
    "title": "Mutation Gate",
    "file": "tasks/043-mutation-gate.md"
  },
  "role": "Mutation Agent",
  "allowed_files": [],
  "forbidden_files": [],
  "relevant_docs": [],
  "prior_artifacts": [],
  "known_constraints": [],
  "verification_expectations": [],
  "handoff_required": true,
  "stop_conditions": [
    "task state changed",
    "forbidden file required",
    "required prior artifact missing"
  ]
}
```

## Required Sections

- current task spec
- role assignment
- relevant docs
- allowed files
- forbidden files
- prior step artifacts
- mutation results if any
- property results if any
- doctest results if any
- known constraints
- verification expectations
- stop conditions
- expected handoff path

## Role Packet Profiles

| Role | Must include | Must not include |
| --- | --- | --- |
| Test Author | Task acceptance criteria, relevant specs, allowed test files, existing fixture conventions. | Implementation plan that assumes production changes. |
| Test Reviewer | Test Author handoff, failing command evidence, acceptance criteria. | Production code diffs except minimal context needed to assess test coupling. |
| Implementer | Approved tests, allowed production files, architecture constraints. | Permission to edit approved tests unless task is returned to Test Author. |
| Implementation Reviewer | Implementation diff summary, allowed/forbidden file lists, public contract docs. | Hidden local assumptions not present in handoff artifacts. |
| Mutation Agent | Verified implementation handoff, mutation config, baseline command, report expectations. | Authority to waive survivors. |
| Mutation Triage Agent | Mutation report, operator metadata, relevant tests, equivalent-risk policy. | Permission to change mutation statuses. |
| Property Test Agent | Invariant categories, seed policy, target modules, existing property fixtures. | Nondeterministic generation rules. |
| Doctest Agent | Changed docs, doctest block specs, snapshot rules, CLI/config/report contracts. | Authority to update expected output without semantic review. |
| Verifier | All prior handoffs, task spec, required commands, skipped-stage reasons. | Permission to patch code during final verification. |

## Context Size Strategy

Packets should include references before bulk content.

Priority order:

1. active task file
2. role spec
3. relevant contracts
4. prior handoffs
5. failing command evidence
6. selected code excerpts

Large artifacts should be summarized with paths to full files.

Maximum packet strategy:

- keep packet body focused on one role
- prefer paths plus concise summaries for artifacts over pasted logs
- include only source excerpts needed for the role decision
- replace repeated docs with stable doc references
- preserve exact commands and diagnostics even when summarizing

If a packet would exceed the context budget, the Orchestrator must split the task or create a prerequisite summarization artifact. It must not omit required constraints.

## Stale Context Handling

A subagent must stop and report stale context when:

- task state changed after packet creation
- allowed files differ from queue metadata
- prior artifact referenced by packet is missing
- repository tests no longer match packet evidence

Stale context is resolved by Orchestrator issuing a fresh packet.

## Stale Context Artifact

When a subagent stops for stale context, it emits:

```json
{
  "schema_version": "zentinel.pipeline.stale_context.v1",
  "task_id": "043",
  "role": "Mutation Agent",
  "reason": "allowed_files differ from queue metadata",
  "packet_id": "043-mutation-agent-001",
  "required_refresh": [
    "tasks/queue.json",
    "tasks/status.json",
    "artifacts/pipeline/043/handoffs/04-implementation-reviewer.json"
  ]
}
```

The Orchestrator then generates a replacement packet and records the stale packet as superseded.
