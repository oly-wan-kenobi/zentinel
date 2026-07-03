// Layer: deterministic_core
//
// Single source of truth for the zentinel version string. The value is injected
// at build time from build.zig.zon (the published package manifest) via the
// `zentinel_build_options` import, so the build manifest, the public
// `zentinel version` output (re-exported through root.zig), the cache key, the
// AI context, and the doctest engine version (which participates in workspace
// path identity) can never drift. test/version_parity_test.zig pins the
// runtime constants together.
pub const version = @import("zentinel_build_options").version;
