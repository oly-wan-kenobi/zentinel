# ADR-0001: Support latest stable Zig only (superseded)

**Status:** Superseded by ADR-0007
**Date:** 2026-05-19

## Supersession Note

This ADR is a historical superseded record. Current zentinel versions follow ADR-0007 and pin Zig `0.16.0`. The decision text below describes the former policy only and must not be used as current implementation guidance.

## Context

zentinel is Zig-native and depends on Zig syntax, build behavior, compiler diagnostics, safety modes, comptime semantics, and source mapping. Supporting multiple Zig releases would multiply the parser and fixture matrix before the product has a stable core.

At the time this ADR was accepted, the project vision, config spec, version policy, and task queue assumed latest stable Zig only.

## Decision

This historical decision supported only the latest stable Zig release for a given zentinel version. Older Zig versions were not compatibility targets. The CLI was expected to fail clearly when it detected an unsupported Zig version.

Experimental backend work could investigate compiler-version coupling, but stable behavior was expected to use the same latest-stable policy.

## Alternatives Considered

- **Support several Zig versions.** Rejected because it creates parser, AST, diagnostics, and fixture ambiguity before core behavior exists.
- **Support whatever Zig is installed.** Rejected because it makes mutation output and report compatibility non-reproducible.
- **Pin to one old Zig release.** Rejected because zentinel should follow the stable language users actively use.

## Consequences

**Positive.** Agents can write one set of fixtures and source-mapping assumptions. Version failures are explicit instead of silent.

**Negative.** Users on older Zig versions must upgrade or use an older zentinel release. Release notes must state the supported Zig version clearly.
