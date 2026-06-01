# Sandbox Security

zentinel runs project test commands against mutated source. That is powerful and potentially dangerous. This document defines safety boundaries for autonomous implementation.

## Threat Model

zentinel must assume test commands can:

- read and write files inside the project
- execute arbitrary local code
- consume CPU and memory
- emit secrets accidentally present in environment variables
- interact with Zig cache directories

zentinel cannot fully sandbox arbitrary local code in Phase 1, but it must avoid making risk worse and must document what it executes.

## Phase 1 Safety Requirements

The runner must:

- execute only configured commands or authorized generated selected test commands
- use a controlled current working directory
- apply one mutant per isolated workspace
- avoid modifying the developer working tree
- enforce timeouts
- bound captured stdout and stderr
- record commands in reports
- not pass secret environment variables to AI prompts

The runner must not:

- run shell-expanded command strings through an implicit shell unless explicitly documented
- delete project cache directories
- mutate files outside the sandbox
- follow symlinks outside the project root for mutation targets
- execute AI-generated commands

## Command Execution Policy

Required command representation:

```text
argv array + cwd + environment policy
```

Config starts with string commands for UX, but zentinel must parse those strings into argv and execute the argv directly. Phase 1 must not use an implicit shell for configured test commands.

The command parser must support only the grammar documented in `docs/CONFIG_SPEC.md`. Unsupported shell syntax is a config error, not a best-effort execution request.

Generated same-file selected commands are authorized only by `docs/TEST_SELECTION.md`. They are built from normalized project-relative Zig source paths, rendered with quoting when path bytes need it, parsed or constructed into argv without a shell, and must pass unmutated preflight evidence before mutant execution can use them for classification. If zentinel cannot construct valid argv for a generated selected command, it must fall back to configured commands and record visible selection-preflight evidence.

Reports must record:

- original command string
- parsed argv
- cwd label
- environment policy label
- whether shell execution was used, which must be `false` for stable Phase 1 behavior
- phase label (`baseline`, `selection_preflight`, or `mutant`)

## Workspace Policy

Sandbox workspaces must live under a deterministic zentinel-controlled temp/cache location, such as:

```text
.zig-cache/zentinel/workspaces/
```

Rules:

- workspace paths are not included raw in stable snapshots
- workspaces are content-isolated by mutant/run identifier
- concurrent workers use distinct writable workspace directories
- local `.zig-cache` and `zig-out` writes are isolated or namespaced per worker or mutant
- shared Zig compiler cache use is allowed only for content-addressed cache entries that cannot be corrupted by concurrent writes
- cleanup failures are warnings unless they risk source corruption
- patch application validates original text before replacement
- workspace, scratch, report, config, and documentation paths are checked with the shared project-root containment guard before filesystem access

No two workers may write the same local cache, output, or temporary build artifact path. This includes `.zig-cache/`, `zig-out/`, generated doctest workspaces, and mutation runner scratch files.

## Allocator Mutation Boundary

Allocator-path mutators are high risk because they can crash the test runner or harness if they rewrite zentinel's own allocation path instead of the target project path.

Rules:

- allocator mutators may target only fixture-controlled code or target modules that receive an injected allocator wrapper explicitly
- the zentinel runner allocator, harness allocator, global allocator setup, and report writer allocator are forbidden mutation targets
- target modules must operate on allocator wrappers passed through the sandboxed command or fixture, not on hidden global state
- allocator failure evidence belongs to the target command evidence in the mutant report, never to runner or harness crash handling
- a crash in zentinel's runner or harness is an internal error, not a killed mutant

## Symlink Policy

Mutation targets must resolve inside the project root.

Allowed:

- ordinary in-tree files and directories

Forbidden:

- mutating a symlink target outside the project root
- using symlink traversal to write outside the sandbox
- using symlink traversal to read config, docs, reports, workspaces, scratch files, or report outputs outside the project root

## Environment Policy

Default runner environment must be minimal and deterministic:

- preserve only variables needed for Zig execution and local tool discovery
- normalize locale-related behavior with fixed `LC_ALL=C` and `LANG=C` unless the platform requires omitting them
- omit secrets from reports
- never include full environment in AI context

The default minimal environment allowlist is exactly `PATH`, `HOME`, `TMPDIR`, `ZIG_GLOBAL_CACHE_DIR`, `ZIG_LOCAL_CACHE_DIR`, `LC_ALL`, and `LANG`. If a variable is absent on the host, zentinel omits it rather than synthesizing a host-specific value; `LC_ALL` and `LANG` are always forced to `C` regardless of the inherited values.

This is implemented, not aspirational: the run command builds the allowlist with `runner.minimalEnviron` from the parent environment and passes it as the child `environ_map` for every baseline and mutant test command (`src/cli.zig`). Because the executor actually restricts the environment to this allowlist, the `environment_policy = "minimal"` recorded in each command result is truthful — the full developer environment is not inherited. Phase 1 still cannot apply OS-level sandboxing (process isolation, filesystem jails); the minimal environment is the environment guarantee it does make.

Future config may allow explicit environment variables, but default behavior should be conservative.

## Output Bounds

Command output excerpts are bounded to 4096 bytes per stream. The bound applies independently to normalized stdout and stderr excerpts before report writing or AI context construction. Full unbounded command output must not be persisted in report v1 or sent to AI providers.

## AI Security Boundary

AI providers receive only privacy-filtered context from registered AI context schemas such as `docs/AI_CONTEXT_SCHEMA.md` for mutation AI and `docs/DOCTEST_AI_INTEGRATION.md` for doctest AI.

AI must not receive:

- full environment variables
- arbitrary files
- sandbox paths with user home directories
- command output beyond bounded excerpts
- secrets matching redaction patterns

AI output must never become a command to execute.

## Security Regression Tests

Future tasks must add tests for:

- patch cannot write outside project root
- symlink escape is rejected
- read-side symlink escape is rejected for docs, config, and AI report inputs
- command timeout is enforced
- output excerpts are bounded
- secret-like environment content is not included in AI context
- original source tree remains unchanged after mutant execution
