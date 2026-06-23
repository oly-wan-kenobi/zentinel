// Layer: deterministic_core
//
// Stable error-code tokens shared across modules (docs/ERROR_CODES.md). These
// are emitted verbatim in diagnostics and are never machine-translated.
//
// This registry holds only codes referenced by more than one module, so the
// shared literal has a single definition. A code emitted from exactly one site
// (e.g. ZNTL_DIFF_SCOPE_FAILED in cli.zig, ZNTL_ZIR_UNSUPPORTED in
// zir_backend.zig, ZNTL_DOCTEST_WORKSPACE_FAILED in doctest/runner.zig) stays a
// literal at that site to avoid a second definition that could drift; every such
// code is still documented in docs/ERROR_CODES.md and pinned by the
// error-code parity test (test/error_code_parity_test.zig).
pub const doctest_unsupported_tag = "ZNTL_DOCTEST_UNSUPPORTED_TAG";
pub const doctest_invalid_block = "ZNTL_DOCTEST_INVALID_BLOCK";
pub const doctest_snapshot_mismatch = "ZNTL_DOCTEST_SNAPSHOT_MISMATCH";
