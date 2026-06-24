# Security Policy

## Supported versions

zentinel is pre-1.0 and under active development. Security fixes are applied to
the latest released version and `main`. Each release pins a single supported Zig
version (currently **0.16.0**); see
[`docs/ZIG_VERSION_POLICY.md`](docs/ZIG_VERSION_POLICY.md).

| Version | Supported |
|---|---|
| latest release / `main` | ✅ |
| older releases | ❌ |

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
pull requests, or discussions.**

Instead, use GitHub's private vulnerability reporting:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability** to open a private advisory.

This keeps the report confidential until a fix is available. Please include:

- a description of the vulnerability and its impact,
- the zentinel and Zig versions (`zentinel version`),
- step-by-step reproduction instructions or a proof of concept,
- any relevant configuration (`zentinel.toml`) or command line.

You can expect an initial acknowledgement within a reasonable time, a
discussion of the issue and remediation, and credit in the release notes once a
fix ships (unless you prefer to remain anonymous).

## Threat model

zentinel compiles and executes mutated copies of *your* source code and runs
*your* test commands — the same trust boundary as running your own test suite.
It does not download or execute third-party code, and the deterministic core
runs fully offline. The opt-in AI features are the only path that can send data
off the machine, and only when explicitly enabled (`ai.enabled = true` and
`ai.remote_allowed = true`), with a redaction layer on the outbound context.

zentinel still constrains the blast radius of mutant execution: per-worker
sandboxed workspaces, a minimal environment allowlist, and report/cache writes
confined to the project root with symlink-escape rejection. The full threat
model and the guarantees zentinel does and does not make are documented in
[`docs/SANDBOX_SECURITY.md`](docs/SANDBOX_SECURITY.md).

If you find a way to escape the sandbox, escalate beyond the documented trust
boundary, or exfiltrate data without the AI features being explicitly enabled,
that is a vulnerability — please report it as above.
