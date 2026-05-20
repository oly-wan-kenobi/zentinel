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

## Agent Rules

Agents adding public examples must:

- use supported block formats
- keep examples deterministic
- include expected output when behavior matters
- avoid hidden setup in prose
- update doctests in the same task as public behavior changes

## Verification

Doctest Agent runs:

```bash
zentinel doctest
zentinel doctest --file <changed-doc>
```

When mutation-aware doctests apply:

```bash
zentinel doctest --mutate --file <changed-doc>
```

Doctest failures block completion unless the active task is explicitly updating expected docs and verifier approves the new deterministic output.
