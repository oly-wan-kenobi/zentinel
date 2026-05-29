# ADR-0009: Library root.zig is the deterministic-core module-export hub

Status: Accepted
Date: 2026-05-29

## Context

The `zentinel` library module is rooted at `src/root.zig` (task 000). Tests
import `@import("zentinel")` and reach code through that single module, so any
new deterministic-core module must be re-exported from `src/root.zig` to be
test-reachable. The shared CLI command dispatch also lives in `src/root.zig`
(task 001), because the architecture-layer rule (ADR-0008,
`docs/INTERNAL_API_CONTRACTS.md`) forbids deterministic-core modules from
importing presentation adapters, so the pure dispatch/parse logic cannot live in
`src/cli.zig`.

Consequently `src/root.zig` must be edited by essentially every task that adds a
core module or extends shared dispatch. Tasks 000–002 each needed it, and an
audit of the queued backlog found 42 tasks that introduce `src/*.zig` modules
and would each require `src/root.zig`. Listing `src/root.zig` in every task's
`allowed_files` is brittle: it re-blocks every source task and must be
remembered for every future inserted task.

## Decision

Treat `src/root.zig` as project-wide module-hub infrastructure: a global
`allowed_files` scope exception, like the task-control files and the
docs-to-tests gap registries. Any active task may edit `src/root.zig` to
re-export the deterministic-core modules it introduces and to wire shared CLI
dispatch, without listing `src/root.zig` in its `allowed_files`.

Edits to `src/root.zig` are disciplined, not unrestricted: they are limited to
deterministic-core module re-exports and shared-dispatch wiring for the active
task. The architecture-layer validator still forbids deterministic-core from
importing adapter layers, and reviewers check ownership; a task must not place
unrelated product logic in `src/root.zig`.

## Alternatives Considered

- Add `src/root.zig` to the `allowed_files` of all 42+ affected tasks. Rejected:
  brittle, large mechanical churn, and must be re-applied to every future task.
- Change `build.zig` so each core module is its own importable module and tests
  import them directly. Rejected: it relocates the hub to `build.zig` (more
  fragile and owned by task 000) and breaks the established `@import("zentinel")`
  test convention from tasks 000–002.
- Test core modules via relative `@import("../src/...")` paths. Rejected:
  inconsistent with the established convention and does not help tasks that
  extend the shared dispatch living in `src/root.zig`.

## Consequences

- Tasks that introduce a core module or extend shared dispatch edit
  `src/root.zig` without an `allowed_files` change; the validator treats it as a
  scope exception (`is_global_scope_exception`).
- `src/root.zig` grows as the re-export hub. This is acceptable under the
  sequential one-task-at-a-time model; if it becomes unwieldy a future ADR may
  split exports into a dedicated aggregation module.
- The "re-exports and dispatch wiring only" discipline is enforced by review and
  the architecture-layer validator rather than by diffing `src/root.zig`, mirroring
  how the gap-registry row-scoped exception is handled.
