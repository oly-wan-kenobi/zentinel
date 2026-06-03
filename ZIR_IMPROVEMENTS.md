# ZIR Backend Improvements — ledger

- Pick rule: FIRST `todo` top-to-bottom (that is the priority order).
- Statuses: `todo` · `wip` · `done` · `descoped` (with a one-line evidence-backed reason).
- The ZIR backend lives in `src/zir_backend.zig` (`fromTree`/`listFromTrees` + the resolver:
  `expectedAstTag`/`resolveNode`/`mutationFor`); the CLI path is `src/cli.zig` `runListMutants`;
  tests are `test/zir_backend_test.zig` and `test/cli_backend_experiment_test.zig`.

**Progress:** 5/5 done (ZIR-5 partial via escape hatch: collision loss ~22% → ~10%, residual 3c-guarded)

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

- [x] `done` **ZIR-3** · commit `4e443a6` · Harden the resolver (3a version-guard ✓ · 3b reopened → ZIR-5 · 3c audit ✓)
  - **3a — version guard `done`:** `listFromTrees` takes the discovered toolchain and declines
    (`error.UnsupportedZigVersion`) on anything but pinned `0.16.0` via `toolchainSupported`
    (reusing `zig_version.classify`); the CLI prints a clear `--backend zir requires Zig 0.16.0`
    diagnostic. *Proof:* non-`0.16.0` / nightly / not-found all decline; `0.16.0` is accepted.
  - **3b — exact decl-base tracking `reopened` → ZIR-5:** the descope was REFUTED by measurement.
    Running the 3c audit over `src/` shows the innermost-base collision drops **315/1455 (~22%)** of
    binary-operator sites (436 anomalies), so "the parity tests net the heuristic" is false — the
    parity fixtures are collision-free and never exercised it. Detection (3c) is not a fix. Carried
    to ZIR-5, which tries a cheaper claim-aware resolution before the fragile structural descent.
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

- [x] `done` **ZIR-5** · commit `2b33e93` · Fix the resolver collision (reopened from ZIR-3b) — partial, via escape hatch
  - **Goal:** make the ZIR resolver recognize the full binary-operator set on real code by
    eliminating the innermost-base collision (two same-operator sites at equal decl-relative offsets
    resolve to one node, dropping the other). Try a **claim-aware** resolution first — each
    instruction takes the highest-base *unclaimed* node, using only the existing offset machinery —
    and fall back to the structural decl-base descent (`getDeclaration`/`getFnInfo`/`getStructDecl`)
    only if claim-aware cannot guarantee the bijection.
  - **Why (measured — refutes the 3b descope):** over `src/` the ZIR backend emits 1140 candidates
    vs the AST backend's 1455 for the same five operators — **315 lost sites (~22%)**, with **436**
    ZIR-3c `ZNTL_ZIR_RESOLUTION_ANOMALY` diagnostics (worst: `report.zig` 106, `ai/redaction.zig` 73,
    `doctest/matcher.zig` 43). ZIR-only (experimental, opt-in); the default AST backend is unaffected,
    but the ZIR backend is not trustworthy for completeness until this is fixed.
  - **Acceptance:** the 3c anomaly count over `src/` drops to 0 and the AST−ZIR candidate gap for the
    lowered operators is 0 (full real-tree parity); the existing small-fixture parity tests stay green.
  - **Proof:** a regression test with a multi-function fixture (≥2 same-operator sites at equal
    decl-relative offsets) asserting BOTH spans are recognized and zero anomalies — red before (one
    span lost + one anomaly, exactly the ZIR-3c collision case), green after. Corroborate with the
    real-tree AST-vs-ZIR gap (1455 vs 1140 → expect 0).
  - **Result (partial — escape hatch taken):** claim-aware resolution shipped (`resolveNode` returns
    the innermost *unclaimed* node; `.none`=injected, `.exhausted`=residual anomaly). Measured over
    `src/`: ZIR candidates **1140 → 1310**, gap **315 (~22%) → 144 (~10%)**, anomalies **436 → 256** —
    ~54% of the loss recovered, no regressions, no mis-located candidates. The acceptance target
    (gap → 0) was **not** reached: the residual is cross-offset contention the greedy pass cannot
    place, and full closure needs per-instruction declaration tracking (the fragile structural
    descent the escape hatch declines). Per the escape hatch the residual is kept visible by the 3c
    audit and documented here + in `docs/ZIR_BACKEND.md`. The 3c test was repurposed to assert the
    fix (former collision → both sites, no anomaly). Follow-up if the residual matters: wire the
    ZIR-2 oracle into a CI sweep to track it, or attempt bipartite max-matching before going fragile.
  - **Files:** `src/zir_backend.zig`, `test/zir_backend_test.zig`, `docs/ZIR_BACKEND.md`
  - **Escape hatch:** if claim-aware cannot guarantee a bijection (e.g. injected instructions
    contending for real nodes) and the structural descent is too fragile to pin to 0.16.0, keep the
    3c audit as the guard and document the residual loss with the measured number.

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
