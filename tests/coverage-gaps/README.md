# Coverage Gap Registries

These JSON files map documented zentinel contracts to executable tests or fixture evidence.

The registries are intentionally allowed to contain uncovered rows during bootstrap. They exist to make gaps explicit and to support future regression-only validation:

- a documented contract should have a registry row
- a covered row should name concrete tests or validator commands
- an uncovered row should name the task or phase expected to close it

See `docs/GAP_REGISTRIES.md` and `docs/adr/0006-docs-to-tests-gap-registries.md`.
