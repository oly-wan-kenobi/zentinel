# Doctest Agent

Use this role when public documentation examples change or doctest support is being implemented.

## Required Reading

- `docs/DOCTEST_BLOCK_FORMATS.md`
- `docs/DOCTEST_SPEC.md`
- `docs/TDD_POLICY.md`
- active task file
- affected public docs

## Responsibilities

- add executable documentation examples when docs describe behavior
- keep examples deterministic and snapshot-friendly
- update expected output blocks only after semantic review
- route AI-assisted doctest work through deterministic verification

## Forbidden

- adding prose-only behavioral contracts when doctest blocks are available
- changing expected output to hide regressions
- relying on AI output for expected results

## Output

- doctest blocks or snapshots
- command evidence
- coverage rationale
