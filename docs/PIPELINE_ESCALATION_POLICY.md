# Pipeline Escalation Policy

Escalation routes work to deeper review or creates prerequisite tasks. Escalation should not mean asking a human by default.

## Escalation Classes

Each task receives the highest applicable class.

| Task class | Typical scope | Required roles | Required gates |
| --- | --- | --- | --- |
| Low-risk | Narrow docs clarification, metadata-only change, non-contract typo. | Test Author, Implementer, Verifier. | Task-system validation; targeted check for changed file. |
| Normal | Single-module behavior with clear contract and local tests. | Test Author, Test Reviewer, Implementer, Implementation Reviewer, Verifier. | Unit/fixture tests; snapshots when output changes. |
| High-risk | Shared models, reports, runner, cache, mutation classification, public schemas. | Normal roles plus Property Test Agent or Mutation Agent as applicable. | Unit tests, property tests for invariants, mutation gate when mutation-testable. |
| Compiler-internal | AST/ZIR/AIR, source mapping, Zig version coupling, compile-error classification, safety modes. | High-risk roles plus Architecture Reviewer. | Source mapping fixtures, property tests, mutation gate, architecture review. |
| Architecture | Roadmap, public contracts, task system, module boundaries, backend stability. | Phase Planner, Architecture Reviewer, Test Reviewer for executable contracts, Verifier. | Contract validation, task-system validation, doctest readiness for public examples. |

Required gates are monotonic. Escalating a task may add gates, but must not remove gates required by a lower class.

## Trigger Matrix

| Trigger | Escalation |
| --- | --- |
| Repeated test failure | Implementation Reviewer and Test Reviewer joint review. |
| Survivor after retry limit | Mutation Triage Agent then Architecture Reviewer if semantic. |
| Nondeterministic output | Verifier blocks completion and creates determinism task. |
| Public contract ambiguity | Architecture Reviewer updates contract task. |
| Dependency request | Apply `docs/DEPENDENCY_POLICY.md`. |
| Compiler internal risk | Architecture Reviewer required. |
| Security boundary uncertainty | Apply `docs/SANDBOX_SECURITY.md`; ask user only if policy is insufficient. |

## Reviewer Requirements

| Condition | Required reviewer |
| --- | --- |
| Public schema, CLI, config, or report contract changes. | Implementation Reviewer and Test Reviewer. |
| Mutator semantics, result classification, or survivor behavior changes. | Mutation Triage Agent. |
| Source spans, AST/ZIR/AIR mapping, Zig version internals. | Architecture Reviewer. |
| New property-test invariant or generator. | Property Test Agent. |
| Public documentation examples. | Doctest Agent once doctest support exists. |
| Sandbox, process execution, filesystem isolation. | Architecture Reviewer and security review against `docs/SANDBOX_SECURITY.md`. |

## AskUserQuestion Boundary

Ask the user only when:

- two product directions are equally valid and irreversible
- security policy does not cover the risk
- dependency policy forbids required progress
- public compatibility must be intentionally broken

Do not ask for routine implementation choices.

## Escalation Artifact

```md
## Escalation
Task:
Trigger:
Evidence:
Attempted recovery:
Required decision:
Recommended autonomous action:
User input required: yes/no
```

Machine-readable variant:

```json
{
  "schema_version": "zentinel.pipeline.escalation.v1",
  "task_id": "043",
  "trigger": "survivor_after_retry_limit",
  "evidence": ["artifacts/pipeline/043/mutation/report.json"],
  "attempted_recovery": ["added boundary fixture", "reran mutation gate"],
  "required_decision": "architecture_review",
  "recommended_autonomous_action": "create focused source-mapping follow-up task",
  "user_input_required": false
}
```

## Escalation Outcomes

An escalation must end in exactly one outcome:

- `retry_same_task`: allowed only within retry limits.
- `return_to_test_author`: required when evidence shows missing or weak tests.
- `create_prerequisite_task`: used for missing infrastructure or unclear contracts.
- `architecture_review_required`: used for compiler-internal or public-contract drift.
- `blocked_needs_user`: allowed only at the AskUserQuestion boundary.

The outcome must be recorded in the handoff artifact and task status.
