# Doctest Policy

Doctests are executable documentation contracts.

## Mandatory Points

Doctests become mandatory when:

- `zentinel doctest` normal execution exists
- public CLI docs change
- public config docs change
- public report examples change
- AI prompt or response examples change
- stable mutator transformations are documented

Mutation-aware doctests become mandatory when `zentinel doctest --mutate` is stabilized for the relevant scope.

## Required Docs

These docs require doctests after support exists:

- `docs/CLI_SPEC.md`
- `docs/CONFIG_SPEC.md`
- `docs/REPORT_FORMAT.md`
- `docs/MUTATOR_SPEC.md`
- `docs/AI_CONTEXT_SCHEMA.md`
- `docs/AI_PROMPT_CONTRACTS.md`
- `docs/DOCTEST_AI_INTEGRATION.md`
- `docs/DOCTEST_SPEC.md`

## Authoring Rules

Anyone adding public examples must:

- use supported block formats
- keep examples deterministic
- include expected output when behavior matters
- avoid hidden setup in prose
- update doctests in the same change as public behavior changes

## Verification

Verification runs:

```bash
zentinel doctest
zentinel doctest --file <changed-doc>
```

When mutation-aware doctests apply:

```bash
zentinel doctest --mutate --file <changed-doc>
```

Doctest failures block completion unless the change is explicitly updating expected docs and the new deterministic output is reviewed.

## Block Formats and Spec

Doctest cases use the block formats in `docs/DOCTEST_BLOCK_FORMATS.md` and the case kinds, identity, and report shape in `docs/DOCTEST_SPEC.md`. The canonical `case.kind` values are `zig_compile_pass`, `zig_test`, `zig_compile_fail`, `cli`, `config`, `config_fail`, and `mutation`; expectation blocks (`text output`, `json expected`, `diagnostic expected`) are snapshot evidence on the producer case, not standalone kinds.

## Snapshot Update Rules

- Snapshot updates are never automatic in a default `zentinel doctest` run.
- A changed expected block (`snapshot` status `updated`) requires recorded approval: the semantic diff is recorded and reviewed before the evidence is accepted.
- A `mismatch` snapshot is a failing case and blocks completion.

## Doctest Evidence

Doctest evidence is recorded as a machine-readable report using the durable `zentinel.doctest.report.v1` JSON Schema from `docs/DOCTEST_SPEC.md`. A failing doctest case or an unreviewed snapshot update blocks acceptance of the change that introduced it.

## Public Docs Coverage

The selected public contract docs are executable through `zentinel doctest`: `docs/CLI_SPEC.md` (CLI), `docs/CONFIG_SPEC.md` (config), `docs/REPORT_FORMAT.md` (report JSON), and `docs/DOCTEST_AI_INTEGRATION.md` (doctest AI JSON). JSON examples are validated as supported subsets (`json expected subset`) rather than full schema validation, so the documented `schema_version` and key fields cannot silently drift. Coverage fixtures live under `test/fixtures/doctest/public_docs/`, so public-docs executability is auditable from the recorded doctest report.
