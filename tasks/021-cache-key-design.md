# 021 Cache Key Design

Sequential guard: start this task only after task 020 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Implement deterministic cache key construction and cache metadata without enabling broad result reuse yet.

## Scope

- Define cache key inputs.
- Hash source content, config, Zig version, backend, operator, mode, command, and Zig cache namespace metadata when it can affect observable command behavior.
- Add cache metadata serialization.
- Keep cache reads disabled for mutation results until a later task validates reuse.

## Files allowed to modify

- `src/cache.zig`
- `src/config.zig`
- `src/mutant.zig`
- `src/runner.zig`
- `test/cache_key_test.zig`
- `test/snapshots/cache_metadata.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/worker_pool.zig`
- `src/ai/**`
- `src/ast_backend.zig`

## Required tests

- Add failing tests for cache key stability.
- Add failing tests that changing source, config, Zig version, mode, command, or Zig cache namespace metadata changes the key.
- Add a failing metadata serialization snapshot.
- Run `zig build test`.

## Acceptance criteria

- Cache keys include all inputs listed in `docs/PERFORMANCE_STRATEGY.md`.
- Cache metadata distinguishes zentinel result cache keys from Zig build-cache reuse metadata.
- Keys are stable across repeated runs.
- Cache metadata is deterministic.
- No stale result reuse is possible because result reads remain disabled or guarded.

## Non-goals

- Parallel execution.
- Cache eviction.
- Remote cache.
- AI output caching.

## Suggested implementation approach

1. Implement pure key construction first.
2. Use fixture content hashes instead of filesystem timestamps.
3. Snapshot metadata with normalized paths.
4. Add integration points without changing run behavior unless tests require it.

## Dogfooding implications

Cache key correctness is required before dogfood runs can become fast and trusted.

## Follow-up tasks

- `tasks/022-dogfood-fixture-run.md`
