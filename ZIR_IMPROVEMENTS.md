# ZIR Backend Improvements — ledger

- Pick rule: FIRST `todo` top-to-bottom (that is the priority order).
- Statuses: `todo` · `wip` · `done` · `descoped` (with a one-line evidence-backed reason).
- The ZIR backend lives in `src/zir_backend.zig` (`fromTree`/`listFromTrees` + the resolver:
  `expectedAstTag`/`resolveNode`/`mutationFor`); the CLI path is `src/cli.zig` `runListMutants`;
  tests are `test/zir_backend_test.zig` and `test/cli_backend_experiment_test.zig`.

**Progress:** ZIR campaign 7/7 done — ZIR/AST achieve full real-tree parity over `src/` (ZIR-7 max-matching closed the resolver gap to 0; ZIR-6 oracle sweep keeps it honest). One open follow-up in a new track: **SEM-1** (compiler-oracle semantic filter, the alternative to an AIR backend — see "Beyond ZIR" below). SEM-1 is split into 1a (measurement spike — **done**, `c800e53`), 1b (TCE equivalence/dedup filter — **descoped**: 1a measured 0 equivalents/0 duplicates in the Debug pipeline), 1c (compile-as-classifier — todo, the primary win).

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
    two-function `<` collision → exactly one `<`-token anomaly. *(Superseded by ZIR-7: once maximum
    matching made the per-instruction anomaly a false alarm, the diagnostic was removed and the
    bijection is now guarded by the ZIR-2 oracle + ZIR-6 sweep.)*
  - **Files:** `src/zir_backend.zig`, `src/cli.zig`, `test/zir_backend_test.zig`, `test/cli_backend_experiment_test.zig`, `docs/ZIR_BACKEND.md`

- [x] `done` **ZIR-4** · commit `8ae34dd` · Retire the legacy `fromAst` relabel
  - **Goal:** remove `fromAst` / `isSupported` and the relabel-only unit tests now that
    `listFromTrees` is the live CLI path — one code path for the ZIR backend.
  - **Acceptance:** no remaining `fromAst` references (except git history); the CLI is unaffected;
    docs no longer describe the relabel as a live path; the full suite stays green.
  - **Proof:** the removal compiles and the full `zig_test` suite stays green; a grep confirms the
    dead path is gone.
  - **Files:** `src/zir_backend.zig`, `test/zir_backend_test.zig`, `docs/ZIR_BACKEND.md`

- [x] `done` **ZIR-5** · commit `2b33e93` · Fix the resolver collision (reopened from ZIR-3b) — partial; superseded by ZIR-7
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
  - **Superseded by ZIR-7:** maximum bipartite matching closed the residual to **0** (full
    parity over `src/`), so the partial claim-aware result above is now of historical note.

- [x] `done` **ZIR-6** · commit `95ea7fd` · Differential-oracle CI sweep over the real tree
  - **Goal:** make ZIR-2 the continuous oracle it was built to be — a test that walks `src/` and
    runs `differentialOracle` per file on every `zig build test`, guarding ZIR/AST agreement.
  - **Result:** sweeps 58 files. Asserts the invariant `zir_only == 0` (ZIR never recognizes a
    binary-operator site the AST backend misses — catches AST-mutator bugs and Zig-version drift),
    and ratchets the `ast_only` residual so it cannot silently grow. Baseline `<= 144` at first;
    tightened to `== 0` (exact parity) once ZIR-7 landed.
  - **Files:** `test/zir_backend_test.zig`

- [x] `done` **ZIR-7** · commit `08ae96f` · Maximum bipartite matching (resolver gap → 0)
  - **Goal:** close the ZIR-5 residual without the fragile structural descent — attempt maximum
    bipartite matching, which uses only the existing offset/base data (no compiler internals).
  - **Result:** `matchInstructions` (Kuhn's augmenting paths) matches each recognized instruction to
    a distinct candidate AST node. Over `src/`: ZIR candidates **1310 → 1455 == AST**, gap
    **144 → 0** — full parity for the lowered operators. A maximum matching makes the per-instruction
    anomaly a false alarm (an unmatched instruction with all-claimed candidates is a *surplus*
    lowering, not a lost site — 107 such notes at zero loss), so `ZNTL_ZIR_RESOLUTION_ANOMALY` was
    removed and surplus instructions are dropped silently; completeness is now guarded by the ZIR-2
    oracle + ZIR-6 sweep. The structural decl-base descent (old 3b) is no longer needed.
  - **Proof:** the ZIR-6 sweep tightened to `ast_only == 0`; the ZIR-5 collision test still green
    (both sites, no anomaly); parity tests on collision-free fixtures unchanged.
  - **Files:** `src/zir_backend.zig`, `test/zir_backend_test.zig`, `docs/ZIR_BACKEND.md`

---

## Beyond ZIR — semantic filtering (alternative to the AIR backend)

> Not part of the ZIR-1..7 campaign (which is complete). This is the recommended path
> *instead of* a task-057 AIR backend. AIR is not exposed by `std` (only `Ast`/`Zir` are);
> an AIR backend would have to vendor `Sema`/`Air`/`InternPool` — far more fragile than the
> version-coupled `src_node` offsets ZIR-3/ZIR-7 already fought. So rather than introspect
> post-Sema IR, use the real compiler as a black-box oracle over candidates from **any**
> backend. The semantic payoff is a *filter/classifier* stage, not a new candidate generator.

**SEM-1** `wip` · Compiler-oracle semantic filter (TCE-first) — split into 1a (measurement spike,
done), 1b (TCE equivalence/dedup filter), 1c (compile-as-classifier). Parent stays `wip` until 1b/1c
resolve.
  - **Goal:** a post-generation filter stage that classifies/excludes candidates using the
    pinned compiler as a black box — no IR introspection. Two parts:
    **(a) Trivial Compiler Equivalence (TCE):** compile original + each mutant to a normalized
    artifact (`-femit-llvm-ir`, or `-femit-asm` as a backend-agnostic fallback) and diff —
    identical-to-original ⇒ provably-equivalent mutant (a guaranteed survivor) → exclude;
    identical-to-another-mutant ⇒ duplicate → dedupe.
    **(b) compile-as-classifier:** replace the heuristic `expected_compile` *prediction* with
    the compiler's actual verdict (compiles / errors), so a non-compiling mutant is classified
    empirically rather than guessed.
  - **Why:** delivers the equivalent-mutant + type/compile payoff that motivated AIR, without
    AIR's accessibility wall. TCE is sound-but-incomplete — it only ever excludes *provably*
    equivalent/duplicate mutants (the safe direction, mirroring the `zir_only == 0` invariant) —
    and is published technique (Trivial Compiler Equivalence, Papadakis/Jia/Harman, ICSE 2015).
    (b) makes Sema the type oracle; the runner already compiles per mutant, so marginal cost is low.
    Works for the default AST backend too, not just ZIR.
  - **Files:** new `src/semantic_filter.zig` + wiring in `src/cli.zig` `runListMutants` (and the
    run path); `test/semantic_filter_test.zig`; a `docs/` note (supersedes the AIR-backend plan).
    Reuses the pinned toolchain + the 3a-style version guard.
  - **Escape hatch:** if per-mutant compilation is too costly even with batching/caching, scope (a)
    to a sampled/opt-in audit and keep (b) as the primary win. If `-femit-llvm-ir` isn't stable
    across Zig backends, use `-femit-asm`; if neither artifact is deterministic enough for reliable
    equivalence, descope (a) with the measured flakiness and keep (b).

- [x] `done` **SEM-1a** · commit `c800e53` · TCE measurement spike (evidence to scope 1b)
  - **Goal:** over a sample of real `src/` mutants, compile original vs mutant, diff the normalized
    artifact, and report TWO numbers — how many TCE marks provably-equivalent/duplicate, and the
    per-mutant compile cost. No production code (`scripts/sem1a_tce_spike.py`).
  - **Method (what the spike learned about the artifact):** the linked Mach-O binary embeds a
    **per-link random `LC_UUID`**, so two builds of *identical* source differ — a binary diff marks
    everything non-equivalent and catches nothing (verified). The usable oracle is the **whole-program
    pre-link LLVM IR** (`zig build-exe -fstrip -femit-llvm-ir -fno-emit-bin` with FIXED global+local
    cache dirs): `-fstrip` drops debug-info paths, fixed caches drop the embedded cache path in
    `!DIFile`, and the result is **byte-deterministic for identical source** → IR-identity is a sound
    TCE oracle. `-femit-llvm-ir` worked fine on 0.16 aarch64-macos (no `-femit-asm` fallback needed).
  - **Result — payoff ≈ 0, and a soundness landmine:** over **80** sampled mutants (six stable
    mutators, Debug): **0 confirmed genuine equivalents, 0 duplicates**; per-mutant IR emit **≈ 1.0s**
    warm. The naive exe (`main`) root flagged 13/80 "equivalent", but re-checking each under a
    force-codegen root showed **12/13 were killable mutants in code not reachable from `main`** (their
    patch can't move the exe IR) and **1/13 was a struct method `refAllDecls` does not force-emit** —
    i.e. **every** IR-identical verdict was an *un-codegen'd* site, not a real equivalence. Mechanism:
    in **Debug** (the runner's mode) the optimizer does ~nothing, so TCE's classic wins (`x*1→x`,
    folded/dead branches) essentially don't arise; the only "equivalents" are structurally-dead code,
    which the existing deterministic `equivalent_risks` + `equivalentToCanonical` no-op skip already
    cover. **Soundness:** because lazy codegen silently omits code, any TCE filter built on a
    standalone compile that does not guarantee the mutated site is codegen'd-and-reached would
    **exclude killable mutants** — violating the SOUND-DIRECTION INVARIANT. A sound TCE oracle must
    diff the artifact of the **test binary the runner already builds** (where code-under-test is
    reached via its tests), not a separate standalone compile.
  - **1c-relevant distribution (free, from the same listing):** of 1844 `src/` candidates, **166 are
    heuristic `may_fail`** (the guesses 1c would replace with the compiler's actual verdict); all 80
    sampled compiled (0 compile errors). The runner already compiles each mutant, so 1c's marginal
    cost is ~0.
  - **Files:** `scripts/sem1a_tce_spike.py` (reproducible spike).

- [x] `descoped` **SEM-1b** · commit `—` · TCE equivalence/dedup filter
  - **Reason (evidence-backed, one line):** SEM-1a measured **0 genuine equivalents and 0 duplicates
    over 80 real Debug-mode mutants** — TCE's payoff is *zero* in this project's pipeline because the
    runner compiles at **Debug** (`modes = ["Debug"]`), where the optimizer normalizes nothing, so the
    only IR-identical mutants are structurally-dead code already handled deterministically by
    `equivalent_risks` + `equivalentToCanonical`; a sound version would additionally have to diff the
    runner's own test-binary artifact (standalone compiles silently omit lazily-uncodegen'd code and
    would exclude *killable* mutants), which is disproportionate work for no measured benefit.
  - **Re-analysis note:** SEM-1a's lone "1/13 genuine" candidate (`mutant.zig` `isValidCandidate`
    `return false → return true`) is in fact **provably killable** — it only read as equivalent because
    that struct method is not emitted under either oracle root (the `refAllDecls` method hole). Genuine
    TCE-equivalents in the 80-sample is therefore literally **0**, reinforcing the descope.
  - **Revisit trigger (not a TODO):** only worthwhile if the project later adds an optimized
    (`ReleaseFast`/`ReleaseSafe`) mutation mode where the optimizer *can* normalize equivalent forms;
    even then it must diff the runner's test-binary pre-link IR (fixed caches, `-fstrip`), never a
    fresh standalone compile, and stay opt-in. No code change taken now.
  - **Files:** none (descoped; evidence in `scripts/sem1a_tce_spike.py` + SEM-1a row).

- [ ] `todo` **SEM-1c** · commit `—` · Compile-as-classifier (replace heuristic `expected_compile`)
  - **Goal:** replace the heuristic `expected_compile` *prediction* with the compiler's actual
    verdict (compiles / errors) for each mutant, so a non-compiling mutant is classified empirically.
    1a's primary win: 166/1844 candidates are heuristic `may_fail`; the runner already compiles per
    mutant, so marginal cost ≈ 0.
  - **Proof:** red→green — a named non-compiling mutant is classified by the compiler's verdict
    (not the guess); agreement with the heuristic on a named compiling mutant is unchanged.
  - **Files:** `src/semantic_filter.zig` (or `src/mutant_runner.zig` wiring), `test/...`.

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
