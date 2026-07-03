# Schema Registry

zentinel uses machine-readable schemas to keep reports and AI contracts compatible across versions.

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
| Doctest AI context v1 | `schemas/ai.doctest.context.v1.schema.json` | Doctest AI |
| Doctest AI explain response v1 | Reuses `schemas/ai.explain.response.v1.schema.json`; doctest classifications are included in that shared enum | Doctest AI |
| Doctest AI suggest response v1 | `schemas/ai.doctest.suggest.response.v1.schema.json` | Doctest AI |
| Doctest AI snapshot-review response v1 | `schemas/ai.doctest.snapshot_review.response.v1.schema.json` | Doctest AI |
| Benchmark v1 | `schemas/benchmark.v1.schema.json` | Performance |

## Rules

- JSON examples in docs must match schema intent.
- Schema files are canonical for machine validation once they exist. A row may use `Future` only while its referenced schema file does not exist; once the file is created, the registry row must name it directly.
- Breaking changes require a new schema version.
- Additive optional fields may remain in the same version if they do not affect deterministic semantics.
- Deterministic result fields may not be moved under advisory or AI-owned fields.
- JSON Schema `maxLength: 4096` is a secondary structural guard for command output excerpts. The canonical output excerpt bound is 4096 UTF-8 bytes before JSON emission; implementations must truncate on a safe character boundary before schema validation.

## Validation

Schema validation for reports and AI contracts lives in Zig tests wherever those artifacts are emitted or consumed. Existing schema files are exact implementation targets.

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
zentinel.benchmark.v1
```

Schema file names mirror those versions after dropping the leading `zentinel.` namespace.

## Compatibility

Readers should reject unknown required fields only when the schema demands it. Writers must emit the documented schema version exactly.

AI schemas are advisory. Report schemas are deterministic core contracts.
