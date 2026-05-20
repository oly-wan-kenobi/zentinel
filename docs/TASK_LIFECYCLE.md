# Task Lifecycle

Every zentinel task follows a strict lifecycle. The lifecycle is machine-checkable through `tasks/queue.json`, `tasks/status.json`, and pipeline artifacts.

## Queue States

```text
queued
  -> active
  -> implemented
  -> verified
  -> complete
```

`blocked` and `superseded` are terminal side paths outside the normal success path. These are the only states that may be written to `tasks/queue.json` and `tasks/status.json`:

```text
queued
active
blocked
implemented
verified
complete
superseded
```

Fine-grained work progress is recorded in pipeline artifacts after those artifacts exist. Before task `041`, equivalent progress is recorded in `tasks/STATUS.md`, `tasks/status.json`, and the task completion summary.

## Pipeline Artifact Stages

Pipeline artifacts may use finer stages to describe agent work inside one queue state:

```text
active
  -> tests_authored
  -> tests_reviewed
  -> implemented
  -> reviewed
  -> mutation_checked
  -> verified
  -> complete
```

`tests_authored`, `tests_reviewed`, `reviewed`, and `mutation_checked` are artifact stages only. Agents must not write those names to `tasks/queue.json`, `tasks/status.json`, `tasks/QUEUE.md`, or `tasks/STATUS.md`.

The Task Queue Manager owns lifecycle edits to `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`. Those task-control edits are allowed even when a task's implementation scope does not list the files, and the validator must prove the Markdown and JSON state agree before completion.

Before task `041`, the synchronized task-control files are the active-task lock. After task `041`, the active task must also have the `artifacts/pipeline/<task-id>/locks/active-task-lock.json` evidence defined by `docs/PIPELINE_ARTIFACTS.md`.

## State Rules

| State | Entry requirement | Exit requirement |
| --- | --- | --- |
| `queued` | Task exists and dependencies are complete. | Task Queue Manager activates it. |
| `active` | Exactly one active task lock exists, using task-control files before task `041` and the task-control files plus active-lock artifact after task `041`. | Test Author emits failing-test evidence in the active task's available evidence location. |
| `implemented` | Code compiles and targeted tests pass. | Implementation Reviewer approves scope and design. |
| `verified` | Final verification passed. | Queue/status updated to complete. |
| `complete` | Task status and required artifacts for the active cutover stage are persisted. | Next task may activate. |
| `blocked` | A blocker exists that cannot be resolved within current task scope. | Smallest prerequisite task is queued or the blocker is superseded. |
| `superseded` | A later product or sequencing decision made the task obsolete. | No normal exit. |

## Completion Rule

A task is complete only when:

- all required artifacts for the active cutover stage exist
- all required tests were authored before implementation
- review gates passed when the task risk class or active pipeline stage requires review
- mutation gate passed or produced approved follow-up tasks when mutation tooling is available and required
- property tests passed when required by the active property-test policy and available infrastructure
- doctests passed when required by the active doctest policy and available doctest runner
- verifier evidence is present in the available evidence location
- task-system validator passes

Before task `041`, required artifacts mean task-control status entries and the completion summary. Durable pipeline handoffs, active-lock artifacts, reviews, and verifier reports become required only after the task that introduces the relevant artifact contract has completed. Before task `043`, mutation-gate evidence may be recorded as `pre-gate unavailable` when mutation tooling cannot exist yet. That skip reason must name the missing prerequisite and must not claim mutation evidence was run.

## Blocked Tasks

A task becomes blocked when a required condition cannot be satisfied within task scope.

Blocked task record must include:

- blocker type
- evidence
- attempted recovery
- required prerequisite task
- whether current edits were reverted or preserved behind tests

Normal missing prerequisites should be converted into tasks without asking a human.
