# 038 Doctest Cache

Sequential guard: start this task only after task 037 is complete in `tasks/STATUS.md`. No later-order task may begin until this task is complete.

## Goal

Add deterministic cache keys and cache metadata for doctest extraction and execution.

## Scope

- Define doctest cache key inputs.
- Cache extraction results, planned cases, generated workspace metadata, and execution results where safe.
- Ensure cached and uncached doctest reports are equivalent except cache diagnostics and durations.
- Keep cache invalidation conservative.

## Files allowed to modify

- `src/cache.zig`
- `src/doctest/**`
- `test/doctest_cache_test.zig`
- `test/snapshots/doctest_cache_metadata.json`
- `tasks/STATUS.md`
- `tasks/status.json`

## Files forbidden to modify

- `src/mutators/**`
- `src/ai/**`
- `src/zir_backend.zig`
- `src/air_backend.zig`
- `docs/**`

## Required tests

- Add failing tests that cache keys change when doc content, block line range, Zig version, command kind, or config hash changes.
- Add failing tests that cached and uncached normalized reports are equivalent.
- Add a failing cache metadata snapshot.
- Run `zig build test`.
- Run `python3 scripts/validate_task_system.py`.

## Required property tests

- Cache key construction is deterministic across repeated runs.
- Cache keys are collision-resistant over the documented input tuple.
- Cached results cannot be reused across different Zig versions or doctest engine versions.
- Cache diagnostics do not change pass/fail status.

## Acceptance criteria

- Doctest cache keys include all inputs from `docs/DOCTEST_ARCHITECTURE.md`.
- Cache metadata is deterministic and snapshot-tested.
- Cache reads are safe and conservative.
- Doctest reports remain stable regardless of cache hits.

## Non-goals

- Parallel doctest execution.
- Remote cache.
- AI output caching.
- Mutation-aware doctest caching.

## TDD instructions

Start with pure cache-key tests. Do not enable result reuse until key coverage tests prove every documented input affects the key.

## Suggested implementation approach

1. Extend cache module with doctest-specific key namespace.
2. Use content hashes instead of timestamps.
3. Normalize paths before hashing.
4. Keep metadata human-readable for diagnostics.

## Dogfooding implications

Doctest cache makes executable docs practical in CI and future dogfood runs.

## Follow-up tasks

- `tasks/039-doctest-mutation-experiments.md`
