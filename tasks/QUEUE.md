# zentinel Task Queue

This queue is the human-readable source of truth for sequential AI-agent work. The machine-readable source is `tasks/queue.json`. Execute tasks by the `Order` column. Every machine-readable task entry has an explicit `order` key. Task IDs are stable file identifiers; an inserted prerequisite may use a higher task ID with an earlier decimal order key such as `059.1`. Only one task may be active at a time.

## Rules

- Start with the first dependency-ready `queued` task in execution order.
- Read the selected task file and required docs before marking the task `active`.
- Mark the task `active` in `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json` before editing implementation files.
- Write failing tests before implementation.
- Modify only files allowed by the task. Task Queue Manager lifecycle edits to task-control files and row-scoped gap registry updates under `tests/coverage-gaps/<registry>.v1.json` are the only pre-pipeline exceptions. After task `041` is complete, task-scoped pipeline artifacts under `artifacts/pipeline/<active-task-id>/**` are also allowed for audit evidence only.
- Update `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json` after completion or blockage.
- Run `python3 scripts/validate_task_system.py` after queue or status changes.
- Do not skip a dependency-ready task unless this file is updated with a documented reason.

## Prerequisite Insertion

When a blocked task needs a missing prerequisite, assign the new task the next unused three-digit ID, give it an `order` key before the blocked task, make the inserted prerequisite depend on the immediately previous non-superseded execution-order task, and update dependencies so the blocked task depends on the prerequisite. Do not renumber existing task files. Keep `tasks/QUEUE.md`, `tasks/queue.json`, `tasks/STATUS.md`, and `tasks/status.json` synchronized and run the validator before implementation resumes.

## Queue

| Order | Task | Status | Phase |
| --- | --- | --- | --- |
| 000 | `tasks/068-preimplementation-contract-alignment.md` | complete | 0 |
| 000.0 | `tasks/069-agent-readiness-contract-closure.md` | complete | 0 |
| 000.0.1 | `tasks/070-agent-blocker-contract-closure.md` | complete | 0 |
| 000.0.2 | `tasks/071-agent-contract-finalization.md` | complete | 0 |
| 000.0.3 | `tasks/072-prebootstrap-sequencing-and-contract-cleanup.md` | complete | 0 |
| 000.0.4 | `tasks/073-agent-protocol-readiness-order.md` | complete | 0 |
| 000.0.5 | `tasks/074-same-file-exclusion-sequencing.md` | complete | 0 |
| 000.0.6 | `tasks/075-mutation-gate-availability-policy.md` | complete | 0 |
| 000.0.7 | `tasks/076-doctest-mutation-entry-identity.md` | complete | 0 |
| 000.0.8 | `tasks/077-backlog-audit-task-creation-scope.md` | complete | 0 |
| 000.0.9 | `tasks/078-bootstrap-tdd-order.md` | complete | 0 |
| 000.0.10 | `tasks/079-status-completion-evidence-schema.md` | complete | 0 |
| 000.0.11 | `tasks/080-doctest-survivor-example-identity-guard.md` | complete | 0 |
| 000.0.12 | `tasks/081-task-local-validator-requirements.md` | complete | 0 |
| 000.0.13 | `tasks/082-analysis-findings-closure.md` | complete | 0 |
| 000.0.14 | `tasks/083-agent-tooling-contract-hardening.md` | complete | 0 |
| 000.0.15 | `tasks/084-agent-contract-cutover-closure.md` | complete | 0 |
| 000.0.16 | `tasks/086-validator-scope-and-report-semantic-clarity.md` | complete | 0 |
| 000.0.17 | `tasks/087-dogfood-release-gate-sequencing.md` | complete | 0 |
| 000.0.18 | `tasks/088-ai-input-report-option-clarity.md` | complete | 0 |
| 000.0.19 | `tasks/089-zig-version-verification-blocker-policy.md` | complete | 0 |
| 000.0.20 | `tasks/090-contract-traceability-and-scope-hardening.md` | complete | 0 |
| 000.0.21 | `tasks/091-analysis-risk-cleanup.md` | complete | 0 |
| 000.0.22 | `tasks/092-agent-readiness-follow-up-hardening.md` | complete | 0 |
| 000.0.23 | `tasks/093-agent-enforcement-closure.md` | complete | 0 |
| 000.0.24 | `tasks/094-agent-readiness-validator-closure.md` | complete | 0 |
| 000.0.25 | `tasks/095-autonomous-agent-contract-repair.md` | complete | 0 |
| 000.0.26 | `tasks/096-audit-finding-contract-closure.md` | complete | 0 |
| 000.0.27 | `tasks/097-autonomous-agent-contract-closure.md` | complete | 0 |
| 000.0.28 | `tasks/098-agent-implementation-blocker-closure.md` | complete | 0 |
| 000.0.29 | `tasks/099-handoff-baseline-and-contract-drift-closure.md` | complete | 0 |
| 000.0.30 | `tasks/100-clean-handoff-lifecycle-closure.md` | complete | 0 |
| 000.0.31 | `tasks/101-version-command-and-evidence-closure.md` | complete | 0 |
| 000.0.32 | `tasks/102-agent-workflow-cleanup.md` | complete | 0 |
| 000.0.33 | `tasks/103-contract-ambiguity-cleanup.md` | complete | 0 |
| 000.0.34 | `tasks/104-output-bound-wording-cleanup.md` | complete | 0 |
| 000.0.35 | `tasks/105-architecture-boundary-enforcement.md` | complete | 0 |
| 000.1 | `tasks/000-project-bootstrap.md` | complete | 0 |
| 001 | `tasks/001-cli-shell.md` | complete | 0 |
| 002 | `tasks/002-config-parser.md` | complete | 0 |
| 003 | `tasks/003-test-harness.md` | complete | 0 |
| 004 | `tasks/004-fixture-system.md` | complete | 0 |
| 005 | `tasks/005-version-policy.md` | queued | 0 |
| 006 | `tasks/006-report-schema.md` | queued | 0 |
| 007 | `tasks/007-mutant-model.md` | queued | 1 |
| 008 | `tasks/008-ast-parser-spike.md` | queued | 1 |
| 009 | `tasks/009-ast-candidate-ordering.md` | queued | 1 |
| 009.1 | `tasks/019-same-file-test-exclusion.md` | queued | 1 |
| 010 | `tasks/010-arithmetic-mutators.md` | queued | 1 |
| 011 | `tasks/011-comparison-mutators.md` | queued | 1 |
| 012 | `tasks/012-logical-boolean-mutators.md` | queued | 1 |
| 013 | `tasks/013-patch-sandbox.md` | queued | 1 |
| 014 | `tasks/014-baseline-runner.md` | queued | 1 |
| 015 | `tasks/015-mutant-runner.md` | queued | 1 |
| 016 | `tasks/016-minimal-run-command.md` | queued | 1 |
| 017 | `tasks/017-list-mutants-command.md` | queued | 1 |
| 018 | `tasks/018-report-renderers.md` | queued | 1 |
| 020 | `tasks/020-test-selection-same-file.md` | queued | 1 |
| 021 | `tasks/021-cache-key-design.md` | queued | 3 |
| 022 | `tasks/022-dogfood-fixture-run.md` | queued | 3 |
| 023 | `tasks/023-optional-null-mutators.md` | queued | 2 |
| 024 | `tasks/024-error-path-mutators.md` | queued | 2 |
| 025 | `tasks/025-autonomous-backlog-audit.md` | queued | 0 |
| 026 | `tasks/026-errdefer-mutator.md` | queued | 2 |
| 027 | `tasks/027-integer-literal-boundary-mutator.md` | queued | 2 |
| 028 | `tasks/028-loop-boundary-mutator.md` | queued | 2 |
| 029 | `tasks/029-phase2-semantic-dogfood.md` | queued | 2 |
| 030 | `tasks/030-doctest-conventions.md` | queued | 0 |
| 031 | `tasks/031-doctest-parser.md` | queued | 1 |
| 032 | `tasks/032-doctest-extraction.md` | queued | 1 |
| 033 | `tasks/033-doctest-runner.md` | queued | 1 |
| 034 | `tasks/034-doctest-snapshots.md` | queued | 1 |
| 035 | `tasks/035-cli-doctests.md` | queued | 1 |
| 036 | `tasks/036-config-doctests.md` | queued | 1 |
| 037 | `tasks/037-mutator-spec-doctests.md` | queued | 2 |
| 038 | `tasks/038-doctest-cache.md` | queued | 3 |
| 039 | `tasks/039-doctest-mutation-experiments.md` | queued | 2 |
| 040 | `tasks/040-agent-pipeline-foundation.md` | queued | 0 |
| 041 | `tasks/041-handoff-artifacts.md` | queued | 0 |
| 041.1 | `tasks/063-pipeline-metadata-validator.md` | queued | 0 |
| 042 | `tasks/042-context-packet-system.md` | queued | 0 |
| 043 | `tasks/043-mutation-gate.md` | queued | 1 |
| 044 | `tasks/044-property-test-policy.md` | queued | 1 |
| 045 | `tasks/045-doctest-policy.md` | queued | 1 |
| 046 | `tasks/046-verification-pipeline.md` | queued | 1 |
| 047 | `tasks/047-sequential-task-locking.md` | queued | 0 |
| 048 | `tasks/048-failure-recovery.md` | queued | 0 |
| 049 | `tasks/049-pipeline-escalation.md` | queued | 0 |
| 050 | `tasks/050-parallel-worker-pool.md` | queued | 3 |
| 051 | `tasks/051-fail-fast-impact-analysis.md` | queued | 3 |
| 052 | `tasks/052-performance-benchmarks.md` | queued | 3 |
| 053 | `tasks/053-ai-provider-and-context.md` | queued | 4 |
| 054 | `tasks/054-ai-advisory-commands.md` | queued | 4 |
| 055 | `tasks/055-ai-doctest-assistance.md` | queued | 4 |
| 056 | `tasks/056-zir-backend-experiment.md` | queued | 5 |
| 057 | `tasks/057-air-backend-experiment.md` | queued | 5 |
| 058 | `tasks/058-safety-mode-matrix.md` | queued | 6 |
| 059 | `tasks/059-initial-dogfood-ci.md` | queued | 7 |
| 059.1 | `tasks/061-doctest-mutate-stabilization.md` | queued | 2 |
| 059.2 | `tasks/062-property-generator-infrastructure.md` | queued | 1 |
| 059.4 | `tasks/064-pipeline-artifact-ci-integration.md` | queued | 7 |
| 059.5 | `tasks/065-failure-recovery-validator.md` | queued | 0 |
| 059.6 | `tasks/066-public-docs-doctest-coverage.md` | queued | 1 |
| 059.7 | `tasks/067-ai-doctest-survivor-assistance.md` | queued | 4 |
| 059.8 | `tasks/085-final-dogfood-release-gate.md` | queued | 7 |
| 060 | `tasks/060-release-acceptance-verification.md` | queued | 7 |

## Reordering Policy

Tasks may be reordered only when:

- the current task is blocked by a missing prerequisite
- the new order is documented here
- the new order is documented in `tasks/queue.json`
- `tasks/STATUS.md` records the reason
- `tasks/status.json` records the reason
- no implementation files are partially changed from the blocked task
