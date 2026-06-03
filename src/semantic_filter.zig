// Layer: deterministic_core
//
// Compiler-oracle semantic filter (ZIR_IMPROVEMENTS.md "Beyond ZIR", SEM-1c).
// This is the *compile-as-classifier* half of SEM-1: it replaces the per-operator
// heuristic `expected_compile` *prediction* (a guess made at generation time —
// e.g. arithmetic mutators guess `.may_fail`, comparison/logical/boolean guess
// `.compiles`) with the compiler's *actual* verdict for a mutant that was run.
//
// The runner already compiles every mutant when it executes the test command, so
// the verdict costs nothing extra: the mutant's terminal run status already tells
// us whether the compiler accepted it. SEM-1's TCE/equivalence half (SEM-1b) was
// descoped — measured 0 payoff in this project's Debug pipeline (see the ledger).
//
// Pure: no I/O, no execution. It maps an already-classified run status (produced
// by the deterministic runner authority, I-001) to an empirical `expected_compile`
// bucket; the side-effecting compile is owned by the runner, not this module.
const mutant = @import("mutant.zig");
const report = @import("report.zig");

/// Replace the heuristic `expected_compile` prediction with the compiler's actual
/// verdict, derived from the mutant's terminal run status. A definitive verdict
/// exists only when the mutant's commands actually reached (and passed or failed)
/// the compiler:
///   - `.compile_error`      -> the compiler REJECTED the mutant  -> `.must_fail`
///   - `.killed` / `.survived` -> tests ran, so it COMPILED        -> `.compiles`
///
/// Ambiguous outcomes carry no compile signal, so the heuristic is kept unchanged:
///   - `.compiler_crash` -> the compiler itself crashed (not a clean accept/reject)
///   - `.timeout`        -> killed before any verdict was observable
///   - `.invalid`        -> the patch never applied, so nothing was compiled
///   - `.skipped`        -> fail-fast skipped this mutant's commands
///
/// Keeping the heuristic on the ambiguous branch is the safe direction: an
/// empirical bucket is only ever asserted when the compiler genuinely spoke.
pub fn empiricalExpectedCompile(
    heuristic: mutant.ExpectedCompile,
    status: report.ResultStatus,
) mutant.ExpectedCompile {
    return switch (status) {
        .compile_error => .must_fail,
        .killed, .survived => .compiles,
        .compiler_crash, .timeout, .invalid, .skipped => heuristic,
    };
}
