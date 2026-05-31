# Performance Strategy

zentinel should feel fast without hiding evidence. Performance work must preserve deterministic IDs, ordering, reports, and result semantics.

## Goals

- minimize repeated Zig compilation work
- run independent mutants in parallel
- reuse safe caches
- stop early when a mutant is killed if configured
- select relevant tests without losing diagnostic clarity
- provide benchmark evidence for regressions

## Caching Strategy

Cache keys must include:

- zentinel version
- Zig version
- Zig compiler cache namespace metadata when local or global Zig cache configuration can affect observable results
- backend name and backend version
- operator name
- source file content hash
- config hash
- test command
- mode
- relevant environment normalization

Cache keys use `backend_version` values such as `ast.v1.zig-0.16.0` rather than a loose backend name when backend mapping, patch generation, or Zig coupling can affect observable results.

Cache entries may store:

- baseline pass result
- generated mutant list
- individual mutant execution result
- parsed source metadata
- test discovery metadata

Cache entries must not store:

- AI output as deterministic evidence
- results from unsupported Zig versions
- data keyed only by file path without content hash

## Zig Cache Reuse

Compilation cost is the primary performance constraint for zentinel. Incremental reuse must use Zig's build cache safely instead of forcing full rebuilds for every mutant.

zentinel should preserve and reuse Zig's own cache where safe:

- use stable cache directories
- avoid deleting project `.zig-cache`
- isolate mutant workspace outputs, local `.zig-cache`, and `zig-out` paths per worker or per mutant when they are writable
- avoid cross-mutant source contamination

Mutant workspaces may share compiler cache inputs only when source content hashes make reuse safe. Result reuse is valid only when the cache key covers source content, config, Zig version, mode, selected test command, backend/operator metadata, and any Zig cache namespace inputs that affect command behavior. A warm Zig build cache may reduce compile time, but it must not change report statuses, ordering, or evidence. Report v1 still requires baseline execution unless a future schema or ADR defines fresh-cache proof.

## Parallel Worker Architecture

```text
candidate list (stable order)
  -> scheduler assigns work
  -> worker applies one mutant in sandbox
  -> worker runs selected tests
  -> worker emits result
  -> collector sorts by canonical order
  -> reporter writes deterministic output
```

Worker count must not affect:

- mutant IDs
- final report order
- summary counts
- cache keys

Concurrent workers must not write to the same local workspace, local `.zig-cache`, or `zig-out` directory. Each worker or mutant gets a dedicated writable workspace and output directory. Sharing is allowed only for read-only inputs or content-addressed compiler cache entries that cannot be corrupted by concurrent writes.

## Mutation Scheduling

Scheduling may optimize for:

- expected runtime
- cached results first
- file locality
- operator priority
- fail-fast configuration

Scheduling decisions must be internal. Reports remain sorted by canonical mutant order.

## Fail-Fast Behavior

Supported fail-fast levels:

| Level | Behavior |
| --- | --- |
| `off` | Run all selected commands. |
| `per_mutant` | Stop commands for a mutant once killed. |
| `run_on_baseline_failure` | Stop entire run when baseline fails. |
| `run_on_invalid` | Stop entire run on internal invalid mutant. |

Default:

```text
per_mutant + run_on_baseline_failure
```

Fail-fast must record skipped commands in result evidence.

## Test Impact Analysis

Impact analysis should start conservative:

1. same-file tests
2. package/build target tests
3. dependency graph tests
4. historical signal

AI must not decide impact. AI may later explain why selected tests missed behavior.

## Benchmark Strategy

Benchmarks should measure:

- mutant generation time
- baseline test time
- per-mutant execution overhead
- cold versus warm Zig build-cache behavior
- cache hit rate
- report serialization time
- worker scaling efficiency

Benchmark fixtures:

- tiny project for overhead
- medium project for realistic source traversal
- allocator/error-heavy project for semantic mutators
- dogfood subset for real zentinel behavior

Benchmark output must be machine-readable and stable enough for trend comparison.

## Budget Authority

Task `052` is the first task that may set numeric CI smoke budgets. Before task `052` is complete, references to a runtime budget mean "budget not established yet" and must not be guessed by agents.

Task `052` must write concrete initial budgets for:

- fixture dogfood runtime
- selected production dogfood runtime
- doctest runtime
- benchmark smoke runtime

Initial CI smoke budgets (wall-clock ceilings for a single smoke run; conservative and revisable by a later performance-budget task):

| CI smoke job | Initial budget |
| --- | --- |
| fixture dogfood runtime | 30 seconds |
| selected production dogfood runtime | 180 seconds |
| doctest runtime | 60 seconds |
| benchmark smoke runtime | 120 seconds |

These are ceilings, not targets: a job that finishes faster is fine; a job that exceeds its budget fails the smoke check. The budgets bound wall-clock time only; the machine-readable benchmark output (`zentinel.benchmark.v1`) records normalized summary counts and the equivalence verdicts, never durations, so trend comparison stays deterministic.

Later dogfood and CI tasks must use those documented budgets or create a prerequisite performance-budget task before claiming completion.

## Performance Invariants

- Correctness and determinism outrank speed.
- Cached and uncached runs must produce equivalent reports except for `diagnostics.cache` and durations.
- Parallel and serial runs must produce equivalent reports except for durations.
- A timeout is a deterministic result with recorded command evidence.
- No performance optimization may skip baseline verification in report v1. A future schema or ADR must define fresh-cache proof before baseline skipping is allowed.
