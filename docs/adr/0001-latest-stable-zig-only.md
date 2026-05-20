# ADR-0001: Support latest stable Zig only

**Status:** Superseded by ADR-0007
**Date:** 2026-05-19

## Context

zentinel is Zig-native and depends on Zig syntax, build behavior, compiler diagnostics, safety modes, comptime semantics, and source mapping. Supporting multiple Zig releases would multiply the parser and fixture matrix before the product has a stable core.

The existing project vision, config spec, version policy, and task queue all assume latest stable Zig only.

## Decision

zentinel supports only the latest stable Zig release for a given zentinel version. Older Zig versions are not compatibility targets. The CLI must fail clearly when it detects an unsupported Zig version.

Experimental backend work may investigate compiler-version coupling, but stable behavior must continue to use the same latest-stable policy.

## Alternatives Considered

- **Support several Zig versions.** Rejected because it creates parser, AST, diagnostics, and fixture ambiguity before core behavior exists.
- **Support whatever Zig is installed.** Rejected because it makes mutation output and report compatibility non-reproducible.
- **Pin to one old Zig release.** Rejected because zentinel should follow the stable language users actively use.

## Consequences

**Positive.** Agents can write one set of fixtures and source-mapping assumptions. Version failures are explicit instead of silent.

**Negative.** Users on older Zig versions must upgrade or use an older zentinel release. Release notes must state the supported Zig version clearly.
