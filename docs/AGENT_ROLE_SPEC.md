# Agent Role Specification

Each pipeline role has explicit responsibilities, forbidden behavior, required artifacts, and verification duties.

## Phase Planner

Responsibilities:

- decompose roadmap phases into tasks
- define task dependencies
- classify task risk
- size tasks for one bounded implementation session
- identify required tests, property tests, doctests, and mutation gates

Forbidden:

- implementing production code
- weakening acceptance criteria for convenience
- skipping dependency analysis

Required artifacts:

- phase plan
- task dependency map
- risk classification
- task queue updates

Verification duties:

- prove each task has one clear owner and bounded allowed files
- confirm dependencies appear before dependent tasks
- confirm required test, property, doctest, and mutation expectations are stated

## Task Queue Manager

Responsibilities:

- maintain `tasks/queue.json`
- maintain `tasks/status.json`
- enforce one active task
- validate task state transitions
- reject out-of-order execution

Forbidden:

- reviewing implementation quality
- approving failed verification
- changing task scope without an artifact

Required artifacts:

- queue update summary
- active lock record
- completion transition record

Verification duties:

- run `python3 scripts/validate_task_system.py`
- ensure Markdown queue and JSON queue describe the same task order
- ensure at most one task is active, implemented, or verified pending completion

## Orchestrator

Responsibilities:

- read active task and governing docs
- classify complexity
- create context packets
- spawn or simulate subagent roles
- route artifacts between roles
- decide escalation according to policy
- coordinate final verification

Forbidden:

- hiding failed subagent outputs
- allowing implementer to weaken tests
- marking completion without verifier evidence

Required artifacts:

- orchestration plan
- context packets
- role assignment log
- escalation log if needed

Verification duties:

- confirm each role received a current context packet
- confirm role outputs are persisted before the next role starts
- confirm escalation decisions cite policy, not preference

## Test Author

Responsibilities:

- write failing tests first
- cover acceptance criteria
- add property tests where required
- add doctests where public docs are affected
- avoid implementation-specific overfitting

Forbidden:

- implementing production code
- weakening existing tests
- making assertions vague

Required artifacts:

- test plan
- files changed
- failing command evidence
- coverage rationale

Verification duties:

- show the exact failing command and failure summary
- identify which acceptance criterion each test protects
- state whether property tests, doctests, or snapshots are required

## Test Reviewer

Responsibilities:

- review test adequacy
- confirm tests fail for the intended reason
- identify missing edge cases
- approve tests before implementation

Forbidden:

- implementing production code
- approving tests that only check implementation details

Required artifacts:

- test review summary
- approved test list
- required changes or approval

Verification duties:

- confirm tests fail before implementation
- reject tests that assert implementation details instead of behavior
- require edge cases for Zig semantics, compile errors, and deterministic ordering when applicable

## Implementer

Responsibilities:

- implement smallest change to pass approved tests
- preserve scope and architecture
- avoid unrelated refactors
- keep deterministic behavior

Forbidden:

- editing approved tests to make implementation pass
- expanding task scope without escalation
- changing public contracts without docs

Required artifacts:

- implementation summary
- files changed
- tests run
- known assumptions

Verification duties:

- show targeted tests passing after implementation
- state any assumptions that affected implementation shape
- prove no approved test was weakened or skipped

## Implementation Reviewer

Responsibilities:

- review implementation against task and specs
- verify no forbidden files changed
- check architecture boundaries
- require cleanup before mutation gate

Forbidden:

- accepting broad refactors
- approving hidden contract changes

Required artifacts:

- review findings
- architecture drift assessment
- approval or required fixes

Verification duties:

- inspect changed files against task allowed and forbidden lists
- confirm public contracts and docs changed together when required
- require escalation for broad refactors or backend boundary changes

## Mutation Agent

Responsibilities:

- run configured mutation checks
- preserve deterministic reports
- identify killed, survived, compile_error, compiler_crash, timeout, skipped, and invalid results

Forbidden:

- deciding equivalent mutants without documented deterministic rule
- suppressing survivors
- using AI as result oracle

Required artifacts:

- mutation report
- command evidence
- survivor list
- invalid mutant list

Verification duties:

- prove baseline passed before mutant execution
- record backend, Zig version, config, worker count, and seed if relevant
- preserve full survivor and invalid-mutant evidence

## Mutation Triage Agent

Responsibilities:

- classify survivors
- identify missing tests or equivalent-risk candidates
- propose follow-up tasks
- escalate meaningful survivors

Forbidden:

- waiving survivors silently
- changing mutation result status
- treating AI explanation as proof

Required artifacts:

- survivor triage report
- classification list
- retry recommendation
- follow-up task list

Verification duties:

- classify every survivor using `docs/MUTATION_GATE_POLICY.md`
- distinguish equivalent-risk from proven deterministic equivalence
- route missing-test survivors back to Test Author

## Property Test Agent

Responsibilities:

- identify invariants
- add deterministic property tests
- define seeds and shrinking expectations
- review edge-case coverage

Forbidden:

- relying on nondeterministic seeds
- replacing precise unit tests with broad weak properties

Required artifacts:

- property test plan
- invariant list
- seed policy
- property test results

Verification duties:

- record explicit seeds and generated case counts
- confirm repeat runs with the same seed are stable
- include minimized counterexample evidence when a property fails

## Doctest Agent

Responsibilities:

- ensure public examples use supported doctest blocks
- run doctests when available
- review snapshot stability
- identify missing executable documentation

Forbidden:

- updating expected output without semantic review
- using prose-only contracts where doctests are required

Required artifacts:

- doctest report
- docs changed
- snapshot diff summary
- missing doctest recommendations

Verification duties:

- confirm doctest case IDs and extraction order are deterministic
- review snapshot diffs semantically before approval
- ensure public examples have hidden setup encoded as executable blocks

## Verifier

Responsibilities:

- run final verification pipeline
- check validator output
- compare required artifacts against task criteria
- authorize completion state

Forbidden:

- modifying production code to fix failures
- ignoring failed gates
- marking task complete without evidence

Required artifacts:

- verification report
- command list
- pass/fail status
- residual risk summary

Verification duties:

- run stages in `docs/VERIFICATION_PIPELINE.md` order
- fail fast on task-system, compile, baseline, or invalid-mutant failures
- verify all required handoff artifacts exist before completion

## Architecture Reviewer

Responsibilities:

- review design boundary changes
- check compiler-tooling risks
- protect AST default and deterministic core
- review ZIR/AIR experimental isolation

Forbidden:

- approving architecture drift without doc updates
- allowing AI to influence deterministic core semantics

Required artifacts:

- architecture review
- risk assessment
- required doc updates

Verification duties:

- confirm AST remains the stable default
- confirm ZIR/AIR behavior is experimental and explicitly opted in
- reject changes that let AI determine deterministic correctness
