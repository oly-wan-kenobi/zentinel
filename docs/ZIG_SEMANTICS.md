# Zig Semantics

zentinel exists to understand Zig-specific behavior. This document defines semantic areas that mutators, runners, reports, and AI prompts must treat carefully.

## Supported Zig Version

zentinel supports only the latest stable Zig version. See `docs/ZIG_VERSION_POLICY.md`.

No compatibility shims may be added for older Zig releases unless the policy changes.

## Same-File Tests

Zig commonly places tests inside the same file as implementation:

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add" {
    try std.testing.expectEqual(@as(i32, 3), add(1, 2));
}
```

Default behavior:

- production declarations in a file may be mutated
- `test` declaration bodies are not mutated
- test names and test-only helper code inside `test` bodies are not mutated

Rationale: mutating tests measures test fragility, not production behavior.

## Comptime

`comptime` affects both value computation and code shape. zentinel must distinguish:

- runtime branches
- compile-time branches
- type-level calculations
- generic function instantiations
- inactive branches that may not compile

Compile-time mutations may produce compile errors. These are valid results when expected by the operator contract.

## Error Unions

Error unions encode explicit failure paths. zentinel must preserve whether a mutation targets:

- error propagation with `try`
- local handling with `catch`
- error cleanup with `errdefer`
- explicit error returns

Reports should name the affected error path when source context makes it clear.

## Optionals

Optionals represent absence as a first-class value. zentinel must handle:

- `orelse`
- `.?`
- comparisons with `null`
- optional payload capture
- optional defaults

Mutations should avoid pretending that optional handling is just boolean logic. Null-path coverage is a primary diagnostic signal.

## Allocators

Allocators are behavior-bearing dependencies in Zig. Mutation testing must respect:

- allocation failure paths
- cleanup responsibilities
- leak detection through `std.testing.allocator`
- ownership transfer
- `defer` and `errdefer` cleanup

Allocator mutators remain constrained until zentinel has a deterministic harness for failure injection.

## Safety Modes

Zig safety and optimization modes affect behavior. zentinel must record the configured mode for every run.

Supported modes:

```text
Debug
ReleaseSafe
ReleaseFast
ReleaseSmall
```

Future mode intelligence should report differences clearly:

```text
Killed in Debug, survived in ReleaseFast.
```

This is diagnostic evidence, not an automatic quality judgment.

## Undefined Behavior and `unreachable`

Mutations involving `unreachable`, bounds checks, integer overflow, and invalid enum values may behave differently by mode. zentinel must:

- capture the mode
- classify process exits deterministically
- avoid claiming semantic equivalence without proof
- preserve compiler output evidence for compile failures

## Build System

Zig projects are often tested through `build.zig`. zentinel must support:

- `zig test <file>` for fixture and simple projects
- `zig build test` for normal projects
- configured custom test commands
- Zig cache reuse without cross-mutant contamination

The runner must normalize command evidence in reports.

## Source Formatting

zentinel does not format user source. Patches should preserve the smallest source replacement needed for a mutant.

When parentheses are required to preserve precedence, the backend must add them deterministically and include the exact replacement in the report.

## Semantic Reporting

Reports should use Zig-native terms:

- optional fallback
- error path
- allocator cleanup
- comptime branch
- safety mode
- same-file test
- compile error

Reports should avoid academic mutation jargon when a compiler-native phrase is clearer.
