# Zig Version Policy

zentinel pins Zig `0.16.0` for this zentinel version.

## Policy

| Rule | Requirement |
| --- | --- |
| Supported version | `0.16.0` |
| Other stable versions | Not supported for this zentinel version. |
| Nightly builds | Not supported for stable behavior. |
| Experimental backend adapters | May have separate guards, still keyed to the pinned supported Zig version. |
| CI | Must verify Zig `0.16.0` before running product tests or mutation jobs. |

## Rationale

Zig evolves quickly. Supporting multiple versions would force zentinel to preserve parser behavior, compiler diagnostics, compiler-internal adapters, and build-system differences across a moving matrix. Pinning one supported version keeps fixtures, source mapping, and report evidence reproducible for autonomous agents.

The pin is a product contract, not a lookup result. ADR-0007 supersedes ADR-0001 and fixes the supported compiler at Zig `0.16.0` until a future ADR and task update the pin deliberately.

## Version Detection

Commands that need Zig must run:

```bash
zig version
```

The version check must:

- parse the Zig version
- compare it with zentinel's compiled-in pinned supported Zig version
- fail fast when unsupported
- include remediation text

Example diagnostic:

```text
unsupported Zig version: <detected-version>
zentinel requires Zig 0.16.0
install Zig 0.16.0 or use a zentinel release that supports your compiler
```

When task `005` is implemented, the agent must store the compiled-in supported version in one version-policy module, run `zig version` in the implementation environment, and record durable verification evidence: pinned supported Zig version, local `zig version`, and match or mismatch result. No live latest-stable lookup is required for task `005`. Agents must not infer a different supported version from chat history, examples, installed toolchains, or unrelated documentation.

## Config Contract

Config accepts:

```toml
[zig]
version = "0.16.0"
```

The config value must match the pinned supported version for this zentinel release. Aliases such as `latest-stable` are not accepted in v1 because they obscure which compiler version produced reports and cache keys.

## CI Contract

CI must:

- install Zig `0.16.0`
- print `zig version`
- fail before tests when the version is unsupported
- not run mutation jobs on unsupported versions

## Experimental Backends

ZIR and AIR are more tightly coupled to compiler internals than the AST backend. They must include:

- adapter version checks
- clear diagnostics for unsupported compiler internals
- no fallback to approximate source mapping

Experimental backend breakage must not affect AST backend stability.
