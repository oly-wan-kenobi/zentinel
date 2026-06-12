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
- use a bounded discovery timeout and classify timeout or execution failure as Zig not found
- include remediation text

Example diagnostic:

```text
unsupported Zig version: <detected-version>
zentinel requires Zig 0.16.0
install Zig 0.16.0 or use a zentinel release that supports your compiler
```

The compiled-in supported version lives in one version-policy module. Verification runs `zig version` and records the pinned supported Zig version, the local `zig version`, and the match or mismatch result. No live latest-stable lookup is required, and a different supported version must never be inferred from examples, installed toolchains, or unrelated documentation.

Verifying the version string is necessary but not sufficient for the AST backend. The `std.zig.Ast` parser API surface that the stable backend depends on is also pinned to Zig `0.16.0`. That API surface is verified and recorded against an installed Zig `0.16.0` rather than assumed; see the Parser API Surface section of `docs/AST_BACKEND.md`. This is verification of the pinned compiler's API, not inference of a different supported version.

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

ZIR is more tightly coupled to compiler internals than the AST backend. It must include:

- adapter version checks
- clear diagnostics for unsupported compiler internals
- no fallback to approximate source mapping

Experimental backend breakage must not affect AST backend stability.
