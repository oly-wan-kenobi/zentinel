# ADR-0002: AST backend is the stable default

**Status:** Accepted
**Date:** 2026-05-19

## Context

zentinel needs reliable source spans, deterministic candidate ordering, and stable reports early. Zig compiler internals can expose richer semantic information, but ZIR and AIR are more version-coupled and harder to make stable.

The roadmap, architecture, backend specs, config spec, and tasks all preserve AST as the default path.

## Decision

The AST backend is zentinel's stable default backend. ZIR and AIR are experimental opt-in backends until docs, fixtures, source mapping, schema compatibility, and dogfood evidence justify promotion.

Default config and `zentinel init` must not enable ZIR or AIR.

## Alternatives Considered

- **Start with ZIR or AIR.** Rejected because source mapping and compiler-version coupling would dominate the bootstrap.
- **Expose all backends equally.** Rejected because users and agents need one stable path.
- **Hide experimental backends entirely.** Rejected because exploration is valuable when explicitly labeled and isolated.

## Consequences

**Positive.** Stable reports can ship earlier. Experimental work cannot destabilize default CI.

**Negative.** Some semantic mutations arrive later or remain preview-only until AST limitations are addressed.
