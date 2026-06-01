# CODEX Findings Follow-Up 2

Read-only adversarial audit of zentinel filesystem, path traversal, and symlink safety.

Date: 2026-06-01
Scope: `/Users/oli/Projects/zentinel`
Mode: read-only audit; no source or task-control changes were made during the audit.

## Required Context Read

- `AGENTS.md`
- `tasks/QUEUE.md`
- `tasks/queue.json`
- `tasks/STATUS.md`
- `tasks/status.json`
- `docs/VISION.md`
- `docs/NON_GOALS.md`
- `docs/GLOSSARY.md`
- `docs/AGENT_GUIDE.md`
- `docs/AUTONOMOUS_AGENT_PROTOCOL.md`
- `.agents/README.md`
- `.agents/ORCHESTRATOR.md`
- Relevant behavior specs, including `docs/TDD_POLICY.md`, `docs/ARCHITECTURE.md`, `docs/INVARIANTS.md`, `docs/DISCIPLINE.md`, `docs/STYLE.md`, `docs/SANDBOX_SECURITY.md`, `docs/CLI_SPEC.md`, `docs/CONFIG_SPEC.md`, `docs/REPORT_FORMAT.md`, `docs/DOCTEST_SPEC.md`, `docs/DOCTEST_ARCHITECTURE.md`, `docs/AI_CONTEXT_SCHEMA.md`, `docs/PIPELINE_ARTIFACTS.md`, `docs/PERFORMANCE_STRATEGY.md`, and release/pipeline validation docs.

Current task state at audit time:

- `tasks/status.json`: `active_task = null`
- `tasks/status.json`: `next_task = null`

## Findings

### F-1: Config and `init --force` are symlink-blind

Severity: High
Confidence: High

Direct evidence:

- `src/cli.zig:83-85` writes `zentinel.toml` through `dir.writeFile` when `outcome.write_config` is set.
- `src/root.zig:357-364` allows `init --force` to overwrite an existing config.
- `src/cli.zig:118-120` reads config paths through `dir.readFileAlloc`.
- `src/cli.zig:95-103` rejects absolute or `..` explicit `--config` paths, but does not check symlink components.

Inference:

An adversarial checkout can make `zentinel.toml` or an explicit in-root config path a symlink. `check` and `run` may read outside-root config, and `init --force` may overwrite outside-root content.

Governing contract:

- `docs/CLI_SPEC.md`: `init` creates `zentinel.toml` in the project root.
- `docs/SANDBOX_SECURITY.md`: symlink traversal must not write outside the sandbox.

Why tests/validators may not catch it:

`test/cli_test.zig` primarily tests pure dispatch behavior and does not exercise real filesystem symlink reads/writes for `init` or config loading.

Minimal read-only verification:

```bash
nl -ba src/cli.zig | sed -n '68,85p;95,120p'
nl -ba src/root.zig | sed -n '334,365p'
```

Smallest safe remediation direction:

Introduce a shared config-path helper that rejects absolute/`..`, no-follow-stats every existing component, rejects symlinked final targets for writes, and verifies canonical containment before config reads.

### F-2: Normal `zentinel doctest --file` lacks lexical root containment

Severity: High
Confidence: High

Direct evidence:

- `src/doctest_command.zig:41-44` stores `--file` directly in `opts.file`.
- `src/cli.zig:1005-1012` reads `doc_file` directly with `root_dir.readFileAlloc`.
- `src/cli.zig:1133-1137` guards `doctest --mutate --file`, showing the normal doctest path is inconsistent.

Inference:

`zentinel doctest --file ../...` can escape unless the underlying Zig directory API independently rejects it. The repository code itself does not enforce the documented boundary for the normal doctest path.

Governing contract:

- `docs/CLI_SPEC.md`: doctest accepts `--file <path>`.
- `docs/CONFIG_SPEC.md`: paths are interpreted relative to project root and normalized.
- `docs/SANDBOX_SECURITY.md`: tooling must not make filesystem risk worse.

Why tests/validators may not catch it:

The path-containment unit tests cover the shared read helper for AI and mutation-aware paths, not normal doctest execution.

Minimal read-only verification:

```bash
nl -ba src/cli.zig | sed -n '994,1012p;1130,1137p'
nl -ba src/doctest_command.zig | sed -n '36,47p'
```

Smallest safe remediation direction:

Apply `config.isOutsideRoot` or a stronger shared read containment helper before normal doctest reads, then add symlink-aware containment.

### F-3: AI input report and doctest document reads are symlink-blind

Severity: High
Confidence: High

Direct evidence:

- `src/root.zig:452-467` implements `readPathOutsideRootOption` as a pure absolute/`..` string check.
- `src/cli.zig:701-712` validates mutation AI read paths lexically, then reads `report_path` with `root_dir.readFileAlloc`.
- `src/cli.zig:838-864` validates doctest AI paths lexically, then uses `root_dir.access` and `root_dir.readFileAlloc`.
- `src/cli.zig:939-949` validates survivor AI input lexically, then reads the report.

Inference:

An in-root symlink such as `zig-out/zentinel/report.json -> ../../secret` can feed arbitrary outside-root content into AI context. This is especially sensitive because AI providers are allowed to be remote only behind configuration, but the context boundary must still omit arbitrary files.

Governing contract:

- `docs/SANDBOX_SECURITY.md`: AI must not receive arbitrary files.
- `docs/AI_CONTEXT_SCHEMA.md`: AI context is deterministic and privacy-filtered.

Why tests/validators may not catch it:

Read-side tests currently cover absolute paths and `..` segments, while symlink-aware tests are limited to output writes.

Minimal read-only verification:

```bash
nl -ba src/root.zig | sed -n '452,467p'
nl -ba src/cli.zig | sed -n '701,712p;838,864p;939,949p'
```

Smallest safe remediation direction:

Introduce one read helper for all AI/report/doc inputs that rejects absolute/`..`, no-follow-stats every component, resolves real paths, and verifies containment before opening.

### F-4: Mutation workspace fidelity can silently degrade

Severity: High
Confidence: High

Direct evidence:

- `src/cli.zig:370-372` silently skips discovered source files that fail `readFileAlloc`.
- `src/cli.zig:516-518` silently skips files during `list-mutants`.
- `src/cli.zig:239-245` walks the project tree and silently continues on `copyFile` failure.
- `src/cli.zig:268-270` hides cleanup failures with `deleteTree(... ) catch {}`.

Inference:

Unreadable files, disappearing files, permission errors, or symlink-race failures can produce incomplete candidate sets or incomplete mutation workspaces. That can create false compile errors, missing mutants, false survivors, or stale workspace contamination while the run still appears successful.

Governing contract:

- `docs/DISCIPLINE.md` D-202: sandbox cleanup failures must be reported.
- `docs/DISCIPLINE.md` D-301: command failures must not be swallowed.
- `docs/SANDBOX_SECURITY.md`: workspaces must be isolated and avoid mutating the developer tree.
- `docs/INVARIANTS.md` I-002: same content/config/Zig/backend/command must produce the same candidate set and stable IDs.

Why tests/validators may not catch it:

The real integration test copies a small clean fixture into a temporary directory. It does not inject copy, read, permission, or cleanup failures.

Minimal read-only verification:

```bash
nl -ba src/cli.zig | sed -n '239,246p;268,272p;365,373p;511,518p'
```

Smallest safe remediation direction:

Make source-read and tree-copy failures structured run evidence or fatal setup errors. Report cleanup failures as warnings or diagnostics, and avoid successful mutation results when a workspace is known incomplete.

### F-5: Doctest workspaces and mutation-aware doctest reports can write through symlinks

Severity: High
Confidence: High

Direct evidence:

- `src/doctest/workspace.zig:90-97` checks confinement with string-prefix logic only.
- `src/cli.zig:621-630` materializes doctest workspaces with `createDirPath` and `writeFile`.
- `src/cli.zig:1078-1085` writes mutation-aware doctest scratch files under `.zig-cache/zentinel/doctest-mutate`.
- `src/cli.zig:1153-1156` writes the mutation-aware doctest report under `zig-out/zentinel/doctest/report.json` without `outputPathHasSymlink`.

Inference:

Adversarial `.zig-cache` or `zig-out` symlinks can redirect generated snippets, scratch files, or reports outside the project. Scratch files also appear to persist rather than being cleaned up.

Governing contract:

- `docs/SANDBOX_SECURITY.md`: symlink traversal must not write outside the sandbox.
- `docs/DOCTEST_SPEC.md`: snippets are written into generated doctest files.
- `docs/DOCTEST_ARCHITECTURE.md`: doctest workspace behavior must be deterministic.

Why tests/validators may not catch it:

Doctest runner tests inject a mock provider that records planned paths and string confinement. They do not exercise real filesystem symlink attacks.

Minimal read-only verification:

```bash
nl -ba src/doctest/workspace.zig | sed -n '90,97p'
nl -ba src/cli.zig | sed -n '621,630p;1078,1085p;1153,1156p'
```

Smallest safe remediation direction:

Create doctest workspaces through a no-follow, safely opened trusted root; reject symlinked `.zig-cache`/`zig-out` components for all generated writes; clean scratch state or record cleanup diagnostics.

### F-6: Output report symlink guard is check-then-use, and cache errors are hidden

Severity: Medium
Confidence: High

Direct evidence:

- `src/config.zig:224-244` no-follow-stats output path prefixes.
- `src/config.zig:236-239` treats stat errors, including missing components, as non-escape.
- `src/cli.zig:411-418` checks for symlinks, then separately creates directories and writes.
- `src/cli.zig:423-430` treats cache emission as best-effort and swallows write errors.

Inference:

A concurrent symlink swap between the prefix check and write can redirect output. Cache write failure can silently remove cache evidence and affect later expectations without diagnostics.

Governing contract:

- `docs/CONFIG_SPEC.md`: `--output` inherits the same project-root restriction as `report.output_dir`.
- `docs/INVARIANTS.md` I-013: cache keys include every deterministic input, and stale/unsafe cache reuse is worse than no cache.

Why tests/validators may not catch it:

Static symlink tests exist for output components, but there is no race/fault-injection coverage for TOCTOU or cache write failures.

Minimal read-only verification:

```bash
nl -ba src/config.zig | sed -n '213,244p'
nl -ba src/cli.zig | sed -n '411,430p'
```

Smallest safe remediation direction:

Open/create parent chains with no-follow semantics and write through safely opened descriptors. Emit cache write failures as advisory diagnostics rather than hiding them.

### F-7: Pipeline and release artifact validators trust symlink-following and traversal-capable paths

Severity: High
Confidence: Medium

Direct evidence:

- `scripts/validate_task_system.py:906-908` implements `is_project_relative_path` as a lexical absolute/`..` check.
- `scripts/validate_task_system.py:1503-1560` validates pipeline artifacts with `iterdir`, `glob`, and `read_text` under the artifact tree.
- `scripts/release_dogfood_gate.py:84-90` executes script-type `verified_by` paths via `subprocess.run`.
- `scripts/release_dogfood_gate.py:124-132`, `scripts/release_dogfood_gate.py:155-164`, and `scripts/release_dogfood_gate.py:182-186` treat `(ROOT / rel).is_file()` as sufficient evidence existence.

Inference:

A malicious manifest can reference traversal paths or in-root symlinks and have outside-root files counted as evidence. Script-type `verified_by` paths can execute outside the intended repository scope if the path resolves through traversal or symlink.

Governing contract:

- `docs/PIPELINE_ARTIFACTS.md`: artifacts are task-scoped under `artifacts/pipeline/<task-id>/`.
- `docs/PIPELINE_ARTIFACTS.md`: artifacts must not store secrets, raw home paths, or full temp workspaces.

Why tests/validators may not catch it:

Fixture self-tests cover schema and known invalid artifact shapes, not path traversal or symlinked evidence.

Minimal read-only verification:

```bash
nl -ba scripts/validate_task_system.py | sed -n '906,916p;1503,1560p'
nl -ba scripts/release_dogfood_gate.py | sed -n '74,90p;120,140p;147,164p;182,186p'
```

Smallest safe remediation direction:

Centralize Python repository-relative path validation: reject absolute paths and `..`, resolve real paths, require `relative_to(ROOT)`, and reject symlinked executable/evidence paths unless a contract explicitly allows them.

### F-8: Config accepts outside-root `project.root` and `cache.directory`

Severity: Medium
Confidence: High

Direct evidence:

- `src/config.zig:367-371` validates only `report.output_dir` with `outsideRoot`.
- `src/config.zig:386-402` returns `project.root` and `cache.directory` after normalization but without outside-root validation.
- `src/check_command.zig:58-68` validates include/exclude paths, not `project.root` or `cache.directory`.

Inference:

Current runtime mostly ignores `cfg.project_root`, and cache metadata is currently written beside the report rather than under `cfg.cache_directory`, so part of this is latent. If those fields are used later, they can become root-escape footguns.

Governing contract:

- `docs/CONFIG_SPEC.md`: `project.root` is relative to the config file; paths are interpreted relative to project root and normalized.
- `docs/CONFIG_SPEC.md`: `cache.directory` is the cache storage path.

Why tests/validators may not catch it:

Validation rules explicitly call out output containment, but do not yet call out cache/root containment as strongly.

Minimal read-only verification:

```bash
nl -ba src/config.zig | sed -n '367,402p'
nl -ba src/check_command.zig | sed -n '58,68p'
nl -ba docs/CONFIG_SPEC.md | sed -n '120,129p;250,293p'
```

Smallest safe remediation direction:

Decide whether `project.root` and `cache.directory` are supported in this release. If supported, validate them with the same project-root and symlink policy before any use. If not supported, reject non-default values explicitly.

## Direct Protections Observed

- `src/project_model.zig:102-112` sorts discovered source paths before returning them.
- `src/sandbox.zig:32-41` applies patches to a copy and verifies the original text before replacement.
- `src/config.zig:224-244` includes a static no-follow symlink guard for report/cache output path components.
- `src/worker_pool.zig:88-90` uses per-run/per-mutant workspace roots.

These protections are useful, but they do not close read-side symlink traversal, doctest workspace writes, workspace copy fidelity failures, cleanup reporting, or Python artifact path validation.

## Overall Assessment

zentinel does not currently appear safe enough for adversarial checkouts or autonomous dogfooding against untrusted trees.

It is closer to acceptable only under these assumptions:

- the checkout is trusted
- `.zig-cache`, `zig-out`, config paths, report paths, doc paths, and artifact paths contain no malicious symlinks
- no concurrent process swaps path components during checks and writes
- all source files are readable and stable during discovery/copy
- workspace cleanup succeeds
- release and pipeline manifests are trusted

Under adversarial checkout assumptions, root containment and symlink safety remain incomplete.
