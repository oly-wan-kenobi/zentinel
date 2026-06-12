# Dependency Policy

zentinel should minimize dependencies until the core is stable. Every dependency affects reproducibility and bootstrap complexity.

## Default Policy

| Area | Policy |
| --- | --- |
| Runtime dependencies | Avoid during Phases 0-1. |
| Build dependencies | Avoid unless required by pinned Zig `0.16.0` conventions. |
| Test-only dependencies | Avoid unless they are vendored or generated locally. |
| Network downloads | Not allowed in default tests or CI. |
| AI providers | Optional adapters only; default is disabled or stub. |

## Bootstrap Decisions

These choices are fixed for autonomous agents:

- Config parsing starts with a small deterministic TOML subset implemented in-tree.
- The TOML subset must support documented zentinel config examples: tables, strings, booleans, integers, arrays of strings, and comments.
- Unsupported TOML features must fail with clear validation errors.
- AST mutation should prefer pinned Zig `0.16.0` public parser APIs such as `std.zig.Ast` when available.
- If no usable public parser API exists, Phase 1 may use a token-aware source backend limited to documented operators and must keep the module named `ast_backend` until a parser-backed adapter replaces it.
- ZIR work must not use private compiler internals in stable code paths.

## Adding a Dependency

A dependency may be added only when all conditions are met:

1. The active task allows dependency files to change.
2. The dependency is required to satisfy a documented contract.
3. The dependency works with pinned Zig `0.16.0`.
4. The dependency can be pinned reproducibly.
5. Default tests do not require network access.
6. The task adds tests proving failure behavior when the dependency is unavailable or malformed.

If any condition fails, insert a dependency-evaluation task instead of adding the dependency.

## Vendoring

Vendored code must live under:

```text
vendor/
```

Vendored code must include:

- upstream name
- upstream version or commit
- license
- reason for vendoring
- update command or manual update procedure

No vendored dependency may alter deterministic core behavior without tests.

## Dependency Locking

When `build.zig.zon` exists, dependency updates must be intentional and task-scoped.

Agents must not:

- run broad dependency update commands during unrelated tasks
- accept transitive dependency changes without review
- depend on unpinned branches for core behavior

## Rejected Shortcuts

Do not add:

- a TOML dependency merely to avoid implementing the documented subset
- a generic parser that mutates source without exact spans
- a remote service dependency for deterministic behavior
- a dependency that requires network access in default CI
