# Schema Registry

zentinel uses machine-readable schemas to keep reports, AI contracts, and task metadata compatible across autonomous implementation sessions.

## Schema Files

| Schema | File | Owner |
| --- | --- | --- |
| Report v1 | `schemas/report.v1.schema.json` | Reporting |
| AI prompt v1 | `schemas/ai.prompt.v1.schema.json` | AI assistance |
| AI context v1 | `schemas/ai.context.v1.schema.json` | AI assistance |
| AI explain response v1 | `schemas/ai.explain.response.v1.schema.json` | AI assistance |
| AI suggest response v1 | `schemas/ai.suggest.response.v1.schema.json` | AI assistance |
| AI review-tests response v1 | `schemas/ai.review_tests.response.v1.schema.json` | AI assistance |
| Doctest report v1 | `schemas/doctest.report.v1.schema.json` | Doctest |
| Doctest AI context v1 | `schemas/ai.doctest.context.v1.schema.json`; task `055` creates non-survivor flows and task `067` adds the survivor flow | Doctest AI |
| Doctest AI explain response v1 | Reuses `schemas/ai.explain.response.v1.schema.json`; doctest classifications are included in that shared enum | Doctest AI |
| Doctest AI suggest response v1 | `schemas/ai.doctest.suggest.response.v1.schema.json` | Doctest AI |
| Doctest AI snapshot-review response v1 | `schemas/ai.doctest.snapshot_review.response.v1.schema.json` | Doctest AI |
| Pipeline handoff v1 | `schemas/pipeline.handoff.v1.schema.json` | Agent pipeline; task `041` creates the baseline |
| Pipeline active lock v1 | `schemas/pipeline.active_lock.v1.schema.json` | Agent pipeline; task `041` creates the baseline |
| Pipeline context packet v1 | `schemas/pipeline.context.v1.schema.json` | Agent pipeline; task `041` creates the baseline and task `042` refines context semantics |
| Pipeline stale context v1 | `schemas/pipeline.stale_context.v1.schema.json` | Agent pipeline; task `041` creates the baseline and task `042` refines stale-context semantics |
| Pipeline verification v1 | `schemas/pipeline.verification.v1.schema.json` | Agent pipeline; task `041` creates the baseline and task `046` refines verification semantics |
| Pipeline escalation v1 | `schemas/pipeline.escalation.v1.schema.json` | Agent pipeline; task `041` creates the baseline and task `049` refines escalation semantics |
| Task queue v1 | `tasks/schema/queue.v1.schema.json` | Task system |
| Task status v1 | `tasks/schema/status.v1.schema.json` | Task system |

## Rules

- JSON examples in docs must match schema intent.
- Schema files are canonical for machine validation once they exist. A row may use `Future` only while its referenced schema file does not exist; once the file is created, the registry row must name it directly.
- Breaking changes require a new schema version.
- Additive optional fields may remain in the same version if they do not affect deterministic semantics.
- Deterministic result fields may not be moved under advisory or AI-owned fields.
- JSON Schema `maxLength: 4096` is a secondary structural guard for command output excerpts. The canonical output excerpt bound is 4096 UTF-8 bytes before JSON emission; implementations must truncate on a safe character boundary before schema validation.

## Validation

The task system is validated by:

```bash
python3 scripts/validate_task_system.py
```

Implementation tasks must add or keep schema validation for reports and AI contracts in Zig tests whenever they emit or consume those artifacts. Existing schema files are exact implementation targets.

Task `tasks/041-handoff-artifacts.md` creates the baseline pipeline handoff, active-lock, context, stale-context, verification, and escalation schema files. Task `tasks/063-pipeline-metadata-validator.md` consumes those baseline files when implementing deterministic validation. Those baseline files define the minimal subset required for deterministic validation; tasks `042`, `046`, and `049` refine role-specific fields and fixtures for context packets, verification records, and escalation records without weakening the baseline validation guarantees.

Pipeline metadata validation is intentionally standard-library-only. Task `tasks/063-pipeline-metadata-validator.md` implements a project-owned schema subset validator for pipeline artifacts: schema version checks, required fields, additional-property policy, enum and const checks, basic string/integer/boolean/null/object/array shapes, and task/path ownership. Full Draft 2020-12 validation, including arbitrary conditional and reference traversal, requires an explicit future dependency decision.

## Version Naming

Schema version strings:

```text
zentinel.report.v1
zentinel.ai.prompt.v1
zentinel.ai.context.v1
zentinel.ai.explain.response.v1
zentinel.ai.suggest.response.v1
zentinel.ai.review_tests.response.v1
zentinel.doctest.report.v1
zentinel.ai.doctest.context.v1
zentinel.ai.doctest.suggest.response.v1
zentinel.ai.doctest.snapshot_review.response.v1
zentinel.pipeline.handoff.v1
zentinel.pipeline.active_lock.v1
zentinel.pipeline.context.v1
zentinel.pipeline.stale_context.v1
zentinel.pipeline.verification.v1
zentinel.pipeline.escalation.v1
zentinel.tasks.queue.v1
zentinel.tasks.status.v1
```

Schema file names mirror those versions after dropping the leading `zentinel.` namespace. Task schemas live under `tasks/schema/` because they validate the task operating system itself.

## Compatibility

Readers should reject unknown required fields only when the schema demands it. Writers must emit the documented schema version exactly.

AI schemas are advisory. Report schemas are deterministic core contracts.
