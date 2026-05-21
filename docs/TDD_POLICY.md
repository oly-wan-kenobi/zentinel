# TDD Policy

zentinel development is TDD-first. Every task that changes behavior must begin with a failing test, fixture, or snapshot that describes the desired behavior.

In the AI-agent pipeline, test authorship and implementation are separate responsibilities whenever the task is normal risk or higher. The Test Author creates failing evidence, the Test Reviewer confirms that the evidence matches the task contract, and only then may the Implementer change production behavior.

A successful `python3 scripts/validate_task_system.py` run is not product proof. It checks task-system consistency and registered governance guardrails; it does not replace the active task's failing evidence, targeted tests, snapshots, doctests, schemas, semantic validators, or dogfood runs.

Completion evidence must name the failing evidence, tests added, tests run, and a passed task-system validator result. `tests_added` may be empty only for a no-behavior-change task that explicitly records why no new structural guardrail was added.

Current mechanical checks verify recorded evidence fields and role handoffs; they do not independently prove chronological order until pipeline artifact validation covers role timestamps. Agents and reviewers must still enforce D-400 and I-019 as mandatory discipline before that later artifact-level validation exists.

## Required Workflow

1. Read the active task file and referenced docs.
2. Identify the smallest observable behavior.
3. Add or update a test that fails for the correct reason.
4. Run the targeted test and record the failure.
5. Implement the minimum change.
6. Run the targeted test until it passes.
7. Run the broader relevant suite.
8. Run final active-scope validation before marking the task complete.
9. Update task status and documentation only if behavior or contracts changed.

## Test Categories

| Category | Purpose | Examples |
| --- | --- | --- |
| Unit tests | Validate pure functions and local invariants. | Config normalization, ID hashing, report sorting. |
| Fixture tests | Validate mutation behavior on small Zig projects. | Operator before/after transformations. |
| Snapshot tests | Lock deterministic text/JSON output. | CLI help, report JSON, AI prompt payloads. |
| Integration tests | Run real `zig` commands against fixture projects. | Baseline test, mutant kill/survive. |
| Doctests | Validate executable documentation examples. | CLI docs, config docs, mutator before/after examples. |
| Dogfood tests | Mutate zentinel modules. | Internal config parser survivor review. |
| Contract tests | Protect public schemas. | JSON report schema, AI context schema. |
| Pipeline artifact tests | Validate task lifecycle and handoff metadata. | Queue/status validators, artifact schema fixtures. |

## Failing-Test Requirement

For every task file, the implementing agent must state which test failed before implementation. If the behavior cannot be tested before implementation, the agent must add an executable contract fixture or snapshot first.

Acceptable evidence:

```text
zig build test --summary all
test "config rejects unknown backend" failed before parser validation was implemented
```

Unacceptable evidence:

```text
I inspected it manually.
```

## Pipeline Enforcement

The pipeline enforces TDD through role boundaries:

| Role | TDD responsibility | Forbidden behavior |
| --- | --- | --- |
| Test Author | Add the smallest failing unit, property, doctest, fixture, snapshot, or contract test. | Implement production behavior. |
| Test Reviewer | Confirm the failing test checks the intended behavior and fails for the correct reason. | Weaken assertions to make implementation easier. |
| Implementer | Make the approved failing evidence pass with the smallest production change. | Delete, weaken, or skip approved tests. |
| Implementation Reviewer | Check that implementation satisfies tests without broad refactors. | Replace deterministic evidence with opinion. |
| Verifier | Re-run required commands and record reproducible evidence. | Patch implementation during final verification. |

If an Implementer discovers that an approved test is wrong, the task returns to Test Author or Test Reviewer. The Implementer must not edit the test and continue as though the pipeline remained valid.

For low-risk tasks where one agent performs multiple roles, the final handoff must still record the same sequence:

```text
failing evidence -> implementation -> verification
```

## Determinism Tests

Any feature that emits ordered data must include repeatability coverage:

- run the same operation twice in one process when practical
- compare normalized output
- verify stable sort order
- avoid timestamps in snapshots unless explicitly normalized
- avoid map iteration order in reports

Required deterministic surfaces:

- mutant IDs
- mutant ordering
- CLI output
- JSON report entries
- cache keys
- selected test ordering
- AI prompt payload ordering
- doctest case IDs
- doctest extraction order
- doctest normalized output

## Fixture Rules

Mutation fixtures must be small and explicit:

```text
test/fixtures/
├─ arithmetic_boundary/
│  ├─ build.zig
│  ├─ src/main.zig
│  └─ expected/
│     ├─ mutants.json
│     └─ report.json
```

Each fixture must document:

- target source file
- expected operators
- expected compile behavior
- expected killed/survived outcome when tests are executed
- whether same-file tests are present and excluded

## Snapshot Rules

Snapshots should be stable across machines:

- use project-relative paths
- normalize path separators to `/`
- omit absolute temp directories
- normalize duration fields to deterministic sentinel values
- sort object keys where supported
- include schema version

## Testing AI Features

AI features are tested with deterministic stub providers.

Tests must verify:

- prompt JSON shape
- privacy redaction
- provider selection
- response schema validation
- malformed response rejection
- advisory output cannot alter deterministic result fields

Tests must not call live AI services in the default suite.

## Testing Doctest Features

Doctest implementation must be TDD-first like all other behavior.

Tests must verify:

- fenced block extraction with line numbers
- deterministic case IDs and ordering
- invalid block diagnostics
- Zig compile-pass and compile-fail behavior
- CLI output normalization
- JSON expected matching
- config example validation
- snapshot normalization
- cache-key stability when doctest caching exists

Doctest tests must not:

- infer expected output from prose
- update documentation snapshots automatically
- rely on wall-clock timing
- execute network commands
- use AI as an oracle

## Test Command Expectations

Default required command once a Zig project exists:

```bash
zig build test
```

Additional targeted commands are allowed and encouraged:

```bash
zig build test --summary all
zig test test/fixtures/basic/src/main.zig
zentinel run --config test/fixtures/arithmetic/zentinel.toml
```

CI must run the full default deterministic suite without network access.

## Prohibited Testing Shortcuts

Agents must not:

- implement behavior and add tests afterward without first seeing a failing test
- weaken assertions to make a test pass
- update snapshots without reviewing the semantic diff
- skip failing tests unless the active task explicitly allows it
- use AI-generated explanations as test oracles for mutation correctness
- depend on test order unless the order is part of the contract being tested
- merge implementation that bypasses the required pipeline depth in `docs/PIPELINE_ESCALATION_POLICY.md`
