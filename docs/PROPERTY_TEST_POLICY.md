# Property Test Policy

Property tests verify invariants over generated or enumerated inputs. They complement unit tests and mutation tests.

## Required For

Property tests are required for:

- ID generation
- sorting and deterministic ordering
- cache key construction
- source span mapping
- parser/extractor behavior
- normalization and snapshot matching
- config normalization
- report summary derivation
- mutation candidate deduplication

## Availability Cutover

Before task `044` refines this policy and task `062` implements generated property infrastructure, tasks that touch the required surfaces above must add deterministic property-style tests using the test mechanisms available in their allowed scope. Acceptable pre-infrastructure evidence includes enumerated unit tests, repeated-run tests, fixture cases, snapshots, or small table-driven checks that exercise the invariant without generated data.

Generated property-test infrastructure is mandatory only after task `062` is complete and only for tasks whose active scope requires generated coverage. After that cutover, generated property tests must follow the seed, report, and review rules in this document unless a task explicitly records a narrower deterministic reason.

## Mandatory Invariant Categories

| Category | Example |
| --- | --- |
| Determinism | Same input produces same output. |
| Stability | Reordering unrelated input does not affect canonical output. |
| Round-trip | Source offset maps to line/column and back where supported. |
| Isolation | Mutating sandbox output does not alter source input. |
| Monotonicity | Adding unrelated docs does not change existing doctest IDs. |
| Collision resistance | Distinct cache inputs produce distinct keys in tested samples. |

## Seed Policy

- Every randomized property test must use an explicit seed.
- Failing seed must be printed in test output.
- Default CI uses deterministic seed list.
- New seeds may be added by task, not generated silently.

## Review Expectations

Property Test Agent and Test Reviewer check:

- invariant relevance
- input domain coverage
- deterministic seed use
- meaningful shrinking or minimized failure examples
- no replacement of precise unit tests with weak properties

## Reports

Property test report records:

- property name
- seed
- generated case count
- failures
- minimized counterexample if available
