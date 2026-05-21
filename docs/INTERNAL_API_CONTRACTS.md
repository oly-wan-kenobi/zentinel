# Internal API Contracts

This document defines the expected internal module boundaries for zentinel. Exact Zig syntax may evolve, but agents must preserve these contracts unless a task explicitly changes them and updates this document.

## Module Dependency Direction

Allowed dependency direction:

```text
main
  -> cli
    -> command
    -> config
    -> check_command
    -> run_command
    -> list_mutants_command
    -> report

check_command
  -> command
  -> config
  -> zig_version

run_command
  -> command
  -> config
  -> zig_version
  -> ast_backend
  -> test_selection
  -> sandbox
  -> runner
  -> mutant_runner
  -> report

ast_backend
  -> source_map
  -> mutant
  -> mutators/*

mutant_runner
  -> sandbox
  -> runner
  -> report
  -> mutant
```

Forbidden dependency direction:

- `mutant` importing CLI modules
- `report` running commands
- `runner` generating mutants
- `runner` implementing command-string parsing instead of using `command`
- mutators importing AI modules
- deterministic core importing AI provider adapters

## Shared Command Parser Contract

`src/command.zig` owns parsing configured command strings into argv.

Rules:

- parsing is pure and separately tested
- `zentinel check` validates command syntax through this module
- `runner` executes the parsed argv returned by this module
- no implementation path invokes a shell to interpret configured command strings
- shell features rejected by `docs/CONFIG_SPEC.md` stay rejected before any process is spawned

## Allocator Contract

All non-trivial functions that allocate must accept an allocator explicitly.

Rules:

- no hidden global allocators
- tests use `std.testing.allocator` where practical
- ownership is documented in function names or comments when not obvious
- returned owned memory must be freed by the caller
- long-lived structures expose `deinit`

## Error Contract

Use a central error model once implementation reaches error-reporting tasks.

Required fields for reportable errors:

```text
code
phase
message
path
line
column
command
evidence
```

Error code format:

```text
ZNTL_<AREA>_<NAME>
```

Examples:

```text
ZNTL_CONFIG_UNKNOWN_KEY
ZNTL_ZIG_UNSUPPORTED_VERSION
ZNTL_SANDBOX_PATCH_MISMATCH
```

See `docs/ERROR_CODES.md`.

## Core Types

### `SourceSpan`

Required fields:

```text
file: project-relative path
byte_start: usize
byte_end: usize
line_start: u32
column_start: u32
line_end: u32
column_end: u32
```

Rules:

- byte offsets are authoritative
- line and column are 1-based
- `byte_start <= byte_end`
- spans must be validated against the source buffer before patching

### `Mutant`

Required fields:

```text
id
display_id
backend
backend_version
backend_stability
operator
operator_stability
span
original
replacement
expected_compile
equivalent_risks
```

Rules:

- durable `id` is hash-derived
- `display_id` is assigned after canonical sorting for report rendering and is stable only within that report
- `backend_version` is the deterministic backend contract string used for identity and cache keys, for example `ast.v1.zig-0.16.0`
- `backend_stability` is `stable` or `experimental`; `operator_stability` is `stable`, `preview`, or `experimental`
- `replacement` is exact source text for AST-backed mutants
- one mutant contains exactly one source change

### `CommandResult`

Required fields:

```text
original_command
argv
cwd
environment_policy
shell
phase
status
exit_code
timed_out
stdout_excerpt
stderr_excerpt
duration_ms
skip_reason
```

Rules:

- excerpts are bounded
- durations are normalized in snapshots
- `shell` is `false` for stable configured command execution
- `argv` is produced only by `src/command.zig`
- command order follows config/test selection order
- baseline command results cannot be skipped in report v1
- skipped mutant command results carry a deterministic non-empty `skip_reason`

### `MutationResult`

Required fields:

```text
mutant_id
status
mode
commands
evidence
```

Rules:

- status is derived only from command results and patch validity
- AI cannot modify status
- compile errors are distinct from invalid patch generation
- fail-fast behavior records skipped commands as command results with `status = skipped`, not as an implicit counter

## Public Function Shape

Prefer small modules with pure functions first.

Expected module entry points:

```text
config.loadAndValidate(allocator, path) -> Config
zig_version.validate(discovered, required) -> VersionStatus
ast_backend.generate(allocator, project, config) -> []Mutant
test_selection.select(allocator, mutant, project, config) -> TestPlan
sandbox.apply(allocator, project, mutant) -> Sandbox
runner.run(allocator, command, options) -> CommandResult
mutant_runner.run(allocator, mutant, test_plan, options) -> MutationResult
report.writeJson(allocator, report, writer) -> void
```

Names may vary, but responsibilities must not cross module boundaries.

`MutationResult` must include `classifier_source`, a closed enum that names the deterministic authority used for the result: runner command evidence, patch validation, sandbox validation, backend contract validation, or documented skip policy. `classifier_source` is internal evidence for report construction; it must not be populated from AI output.

## Deterministic Sorting Contract

All public APIs returning lists must document their ordering. If no domain order exists, use lexicographic project-relative paths followed by source offsets and stable names.

## Testing Contract

Every module must have:

- direct unit tests for pure logic
- fixture tests for filesystem/process behavior
- deterministic output snapshots for user-visible text or JSON
