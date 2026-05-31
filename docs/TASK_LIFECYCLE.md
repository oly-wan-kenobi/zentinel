# Task Lifecycle

Every zentinel task follows a strict lifecycle. The lifecycle is machine-checkable through `tasks/queue.json`, `tasks/status.json`, and pipeline artifacts.

## Queue States

Task-control state transitions are `queued -> active -> complete`.

```text
queued
  -> active
  -> complete
```

`blocked` is a recoverable side path outside the normal success path. `superseded` is terminal. `implemented` and `verified` are pipeline artifact stages, not task-control states. They are not valid values for current task-control files.

These are the normal states agents may write to `tasks/queue.json` and `tasks/status.json`:

```text
queued
active
blocked
complete
superseded
```

`queued` means a task is not active, blocked, complete, or superseded. It can describe both future tasks with incomplete dependencies and the dependency-ready queued subset that may be activated next.

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

`tests_authored`, `tests_reviewed`, `implemented`, `reviewed`, `mutation_checked`, and `verified` are artifact stages only. Agents must not write those names to `tasks/queue.json`, `tasks/status.json`, `tasks/QUEUE.md`, or `tasks/STATUS.md`.

The `verified` artifact stage is the verification report at `artifacts/pipeline/<task-id>/verification/report.json` (`docs/VERIFICATION_PIPELINE.md`). A report with `status` `passed` and `recommendation` `complete` is the evidence the Task Queue Manager requires before moving the task-control state from `active` to `complete`; a `failed` or `blocked` report keeps the task `active` or moves it to `blocked`. The report itself never edits the task-control files, so artifact stages do not change task-control state.

Failure recovery (`docs/FAILURE_RECOVERY.md`) runs inside these stages: `failed_implementation`, `failed_mutation_gate`, `flaky_verification`, `rollback_required`, `escalated`, `return_to_role`, and `follow_up_created` are recovery artifact stages within the `active` task-control state. Only `blocked` is a task-control state, and a failure stage never transitions directly to `complete`.

The Task Queue Manager owns lifecycle edits to `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json`. Those task-control edits are allowed even when a task's implementation scope does not list the files, and the validator must prove the Markdown and JSON state agree before completion.

Before task `041`, the synchronized task-control files are the active-task lock. After task `041`, the active task must also have the `artifacts/pipeline/<task-id>/locks/active-task-lock.json` evidence defined by `docs/PIPELINE_ARTIFACTS.md`.

## State Rules

| State | Entry requirement | Exit requirement |
| --- | --- | --- |
| `queued` | Task exists in the queue and is not active, blocked, complete, or superseded. Only a dependency-ready queued task has all dependencies complete and may be activated. | Task Queue Manager activates the first dependency-ready queued task by execution order. |
| `active` | Exactly one active task lock exists, using task-control files before task `041` and the task-control files plus active-lock artifact after task `041`. | Run `python3 scripts/validate_task_system.py` while the task is still active before changing queue state to `complete`; then update queue/status to complete. |
| `complete` | Task status and required artifacts for the active cutover stage are persisted. | Next task may activate. |
| `blocked` | A blocker exists that cannot be resolved within current task scope. | Smallest prerequisite task is queued, or the blocker is superseded. After the prerequisite task completes, the blocked task returns to `queued`. |
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

When a prerequisite task is inserted, the blocked task stays `blocked` until that prerequisite is complete. The inserted prerequisite task must depend on the immediately previous non-superseded execution-order task, and the originally blocked task must depend on the inserted prerequisite. After the prerequisite task completes, the blocked task returns to `queued`, clears the blocked-task detail entry, and is selected again only through the normal dependency-ready queue order.

Machine-readable blocked records use this exact shape in `tasks/status.json`:

```json
{
  "blocked_task_details": [
    {
      "task": "043",
      "reason": "Mutation gate cannot run until prerequisite report schema work exists.",
      "blocker_type": "missing_prerequisite",
      "evidence": "Required schema field is not owned by any earlier task.",
      "attempted_recovery": "Inserted prerequisite task with the next unused task ID.",
      "prerequisite_task": "098",
      "required_prerequisite_task": "098",
      "requires_user_input": false,
      "edits_state": "task_control_only",
      "notes": "Return blocked task to queued after prerequisite completes."
    }
  ]
}
```
