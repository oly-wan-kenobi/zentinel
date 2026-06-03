# ZIR Backend Improvements — ledger

- Pick rule: FIRST `todo` top-to-bottom (that is the priority order).
- Statuses: `todo` · `wip` · `done` · `descoped` (with a one-line evidence-backed reason).
- The ZIR backend lives in `src/zir_backend.zig` (`fromTree`/`listFromTrees` + the resolver:
  `expectedAstTag`/`resolveNode`/`mutationFor`); the CLI path is `src/cli.zig` `runListMutants`;
  tests are `test/zir_backend_test.zig` and `test/cli_backend_experiment_test.zig`.

**Progress:** 4/4 done

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

- [x] `done` **ZIR-2** · commit `283b965` · Differential oracle (ZIR vs AST on real files)
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

- [x] `done` **ZIR-3** · commit `4e443a6` · Harden the resolver (3a version-guard ✓ · 3b descoped · 3c audit ✓)
  - **3a — version guard `done`:** `listFromTrees` takes the discovered toolchain and declines
    (`error.UnsupportedZigVersion`) on anything but pinned `0.16.0` via `toolchainSupported`
    (reusing `zig_version.classify`); the CLI prints a clear `--backend zir requires Zig 0.16.0`
    diagnostic. *Proof:* non-`0.16.0` / nightly / not-found all decline; `0.16.0` is accepted.
  - **3b — exact decl-base tracking `descoped`:** `getDeclaration`/`getFnInfo`/`getStructDecl` are
    unstable compiler internals (the same version-coupling fragility 3a guards), and 3c now makes
    the heuristic's only real failure mode — a collision — observable as an anomaly diagnostic, so
    the parity tests + the 3c audit net it without taking on fragile internals. No code change.
  - **3c — resolution audit `done`:** `fromTree` asserts cmp/bool/arith instructions resolve to a
    bijection over distinct AST nodes; a second instruction on an already-claimed node is flagged
    `ZNTL_ZIR_RESOLUTION_ANOMALY` and skipped. *Proof:* clean file → no anomaly; a forced
    two-function `<` collision → exactly one `<`-token anomaly.
  - **Files:** `src/zir_backend.zig`, `src/cli.zig`, `test/zir_backend_test.zig`, `test/cli_backend_experiment_test.zig`, `docs/ZIR_BACKEND.md`

- [x] `done` **ZIR-4** · commit `8ae34dd` · Retire the legacy `fromAst` relabel
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
