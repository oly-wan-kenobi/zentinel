# Zig Version Policy

zentinel supports only the latest stable Zig version.

## Policy

| Rule | Requirement |
| --- | --- |
| Supported version | Current latest stable Zig release. |
| Older stable versions | Not supported. |
| Nightly builds | Not supported for stable behavior. |
| Experimental backend adapters | May have separate guards, still keyed to latest stable. |
| CI | Must verify the configured latest stable Zig version. |

## Rationale

Zig evolves quickly. Supporting older versions would force zentinel to preserve outdated parser behavior, compiler internal adapters, and build-system differences. That would slow the project and increase ambiguity for AI agents.

Latest-stable-only support lets zentinel:

- use current Zig syntax and semantics
- keep mutator behavior clear
- simplify fixture expectations
- avoid compatibility branches
- align ZIR/AIR experiments with one compiler version

## Version Detection

Commands that need Zig must run:

```bash
zig version
```

The version check must:

- parse the Zig version
- compare it with zentinel's compiled-in latest-stable expectation
- fail fast when unsupported
- include remediation text

Example diagnostic:

```text
unsupported Zig version: <detected-version>
zentinel requires latest stable Zig <supported-version>
install the supported Zig version or use a matching zentinel release
```

The exact latest stable value belongs in implementation constants and release notes, not in this policy document. Diagnostic examples in policy docs must use placeholders such as `<supported-version>` instead of hard-coded current release numbers, because this repository intentionally tracks latest stable Zig.

When task `005` is implemented, the agent must verify the official latest stable Zig release from the Zig project release source, then run `zig version` in the implementation environment and confirm the local toolchain matches that release. The task status or release metadata must record durable verification evidence: official release source consulted, official latest stable version, local `zig version`, and match or mismatch result. The compiled-in value must be stored in one version-policy module and recorded in release notes or an equivalent release metadata file when such a file exists. A local `zig version` result alone is not enough to choose the supported version. Agents must not infer the supported version from chat history, stale examples, or unrelated documentation.

If network access or the official release source is unavailable while task `005` is active, the agent must mark the task blocked and insert a prerequisite task instead of guessing the latest stable Zig version. The prerequisite must restore a durable official-source verification path or provide an approved offline mirror/source contract before task `005` resumes.

## Config Contract

Config accepts:

```toml
[zig]
version = "latest-stable"
```

Explicit version strings may be accepted in the future for reproducible release pinning, but they must match the latest stable value for that zentinel release.

## CI Contract

CI must:

- install the supported latest stable Zig version
- print `zig version`
- fail before tests when the version is unsupported
- not run mutation jobs on unsupported versions

## Experimental Backends

ZIR and AIR are more tightly coupled to compiler internals than the AST backend. They must include:

- adapter version checks
- clear diagnostics for unsupported compiler internals
- no fallback to approximate source mapping

Experimental backend breakage must not affect AST backend stability.
