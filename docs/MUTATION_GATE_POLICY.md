# Mutation Gate Policy

Mutation testing is a verification gate after implementation review and before final verification.

## Gate Position

```text
Tests
  -> Implementation
  -> Review
  -> Mutation Gate
  -> Survivor Triage
  -> Final Verification
```

## Required When

Task `043` is the mutation-gate availability cutover. Before task `043` is complete, mutation-gate skip reasons must use `pre-gate unavailable` when the active task changes behavior that would otherwise require the gate but the gate cannot exist yet. The skip reason must name the missing prerequisite and must not claim mutation evidence was run.

After task `043` is complete, mutation gate is mandatory for mutation-testable tasks only when the active scope is mutation-testable and the required runner/report surface exists for that scope. Mutation gate is required for:

- mutator implementation
- runner behavior
- report classification
- config validation with meaningful branches
- test selection
- cache key behavior
- doctest mutation features
- dogfood-sensitive core modules

Mutation gate may be skipped for:

- pure documentation tasks before doctests exist
- task metadata changes
- schema-only tasks with no executable behavior

Skip requires a written reason.

## Blocking Conditions

The gate blocks completion on:

- invalid mutants
- baseline failure
- nondeterministic mutation reports
- new survivors in protected dogfood scope
- untriaged survivors for the active task

Survivors outside protected scope may produce follow-up tasks instead of blocking, but only after triage.

## Survivor Classification

Allowed classifications:

```text
missing_test
weak_assertion
equivalent_risk
compile_mode_specific
fixture_gap
tooling_bug
out_of_scope
needs_architecture_review
```

AI may suggest classification. The triage artifact owns the final advisory classification.

## Equivalent Mutants

Equivalent mutant handling must be conservative.

Rules:

- do not mark equivalent automatically unless a deterministic rule exists
- document evidence
- create follow-up task when uncertain
- never remove survivor evidence from report

## Retry Behavior

If survivors indicate missing tests:

1. Return to Test Author.
2. Add failing test for survivor behavior.
3. Review test.
4. Implement if needed.
5. Rerun mutation gate.

Retry limit:

- low-risk: 1 cycle
- normal: 2 cycles
- high-risk or compiler-internal: 3 cycles then escalate
