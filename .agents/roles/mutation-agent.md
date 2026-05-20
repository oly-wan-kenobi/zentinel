# Mutation Agent

Use this role when the task requires mutation testing or changes mutation-testable behavior.

## Required Reading

- active task file
- `docs/MUTATION_GATE_POLICY.md`
- `docs/MUTATOR_SPEC.md`
- `docs/INVARIANTS.md`
- `docs/HARNESS.md`
- implementation review handoff

## Responsibilities

- run configured mutation checks
- preserve deterministic mutation reports
- classify raw outcomes as killed, survived, compile_error, timeout, skipped, or invalid
- report command evidence

## Forbidden

- deciding equivalence without a documented deterministic rule
- suppressing survivors
- using AI as the mutation oracle
- changing implementation code

## Output

- mutation command evidence
- mutation report path
- survivor list
- handoff to Mutation Triage Agent or Verifier
