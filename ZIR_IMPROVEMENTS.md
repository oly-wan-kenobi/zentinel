# ZIR Backend Improvements — ledger

- Pick rule: FIRST `todo` top-to-bottom (that is the priority order).
- Statuses: `todo` · `wip` · `done` · `descoped` (with a one-line evidence-backed reason).
- The ZIR backend lives in `src/zir_backend.zig` (`fromTree`/`listFromTrees` + the resolver:
  `expectedAstTag`/`resolveNode`/`mutationFor`); the CLI path is `src/cli.zig` `runListMutants`;
  tests are `test/zir_backend_test.zig` and `test/cli_backend_experiment_test.zig`.

**Progress:** 1/4 done

---

- [x] `done` **ZIR-1** · commit `907651e` · Comptime-context-aware `expected_compile`
  - **Goal:** the resolver tracks comptime nesting (`block_comptime` / comptime bodies); a
    binary-operator candidate whose site is comptime-evaluated is emitted with a comptime-aware
    `expected_compile` (not `.compiles`), since comptime evaluation is strict.
  - **Why:** the one genuine in-process signal ZIR has over the AST (no shell-out). Refines
    `expected_compile` accuracy for free.
  - **Acceptance:** a cmp/arith in a comptime context → `expected_compile != .compiles`; the same
    op in a runtime fn stays `.compiles`; runtime parity with the AST recognizers is unchanged.
  - **Proof:** one fixture, one runtime cmp + one comptime-context cmp; assert each candidate's
    exact `expected_compile`. Red before (both `.compiles`), green after.
  - **Files:** `src/zir_backend.zig`, `test/zir_backend_test.zig`
  - **Escape hatch:** if comptime context can't be determined from the public `Zir`, `descoped`
    with evidence.

- [ ] `todo` **ZIR-2** · commit `—` · Differential oracle (ZIR vs AST on real files)
  - **Goal:** a `zir_backend` function that compares the ZIR-recognized binary-operator set against
    the AST recognizers' set per file and reports any `(operator, byte_start, byte_end)` divergence
    — turning parity into a continuous correctness oracle for the default AST backend (catches
    AST-mutator bugs and Zig-version drift).
  - **Why:** high-trust, low-risk; no new mutants, just a check that the two paths agree.
  - **Acceptance:** agreement → zero findings; a constructed divergence → reported with
    file + span + operator.
  - **Proof:** a test asserting no divergence on an agreeing fixture, and a divergence surfaced when
    one side is perturbed. Red→green.
  - **Files:** `src/zir_backend.zig` (+ optional CLI surface), `test/zir_backend_test.zig`

- [ ] `todo` **ZIR-3** · commit `—` · Harden the resolver (3a version-guard · 3b exact base · 3c audit)
  - **3a — version guard:** gate the ZIR path on the discovered Zig version == pinned `0.16.0`;
    emit a clear diagnostic and decline if mismatched (the `src_node` offsets are version-coupled).
    *Proof:* an injected non-`0.16.0` version → the version diagnostic / declines.
  - **3b — exact decl-base tracking:** replace the innermost-base heuristic with the structural
    decl-base descent (`getDeclaration`/`getFnInfo`/`getStructDecl`). **LIKELY `descoped`** —
    fragile compiler-internals, and the parity tests already net the heuristic. Record the reason.
  - **3c — resolution audit:** assert ZIR cmp/bool/arith instructions resolve to a bijection over
    distinct AST nodes; surface anomalies as diagnostics. *Proof:* clean fixture → no anomaly; a
    forced anomaly is flagged.
  - **Do 3a + 3c; descope 3b with a reason.**
  - **Files:** `src/zir_backend.zig`, `src/zig_version.zig` (read-only reuse), `test/zir_backend_test.zig`

- [ ] `todo` **ZIR-4** · commit `—` · Retire the legacy `fromAst` relabel
  - **Goal:** remove `fromAst` / `isSupported` and the relabel-only unit tests now that
    `listFromTrees` is the live CLI path — one code path for the ZIR backend.
  - **Acceptance:** no remaining `fromAst` references (except git history); the CLI is unaffected;
    docs no longer describe the relabel as a live path; the full suite stays green.
  - **Proof:** the removal compiles and the full `zig_test` suite stays green; a grep confirms the
    dead path is gone.
  - **Files:** `src/zir_backend.zig`, `test/zir_backend_test.zig`, `docs/ZIR_BACKEND.md`

---

## Loop discipline (mirrors the DEEP_REVIEW campaign)

- One item per iteration; pick the first `todo`, set it `wip`, finish it, set it `done`.
- **Substance over ceremony:** a real behavior change, never a validator standing in for code.
- **Prove with a red→green regression test:** it FAILS on the current code (show the red via
  `zig_test`) and PASSES after. Assert SPECIFIC behavior — exact `expected_compile` bucket, exact
  diagnostic text, exact divergence flagged, exact candidate set — never aggregate counts.
- **Ground truth via the zigars MCP:** `zig_build` AND the full `zig_test` must both be green.
  Never mark an item green you did not actually run.
- Commit the change + its test together (message starts with the id, e.g. `ZIR-2: …`); commit the
  ledger update separately.
- A deliberate-trade-off item (or sub-part) → `descoped` with a one-line evidence-backed reason and
  no code change (analogous to a refuted finding).
- Blocked or larger than expected → set the row back to `todo` with a short note and stop the
  iteration rather than half-implementing.
- Stop the loop when no `todo`/`wip` remains: print a one-line summary (done/descoped counts).
