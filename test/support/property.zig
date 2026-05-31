// Test support: run a structural property over a deterministic seeded stream and
// record the evidence a property report must carry (docs/PROPERTY_TEST_POLICY.md,
// task 062). This is the harness tests use to drive the seeded generator; it is
// not product code and lives only under test/.
const std = @import("std");
const gen = @import("zentinel").property.generator;

pub const Outcome = struct {
    /// The seed the run started from — always recorded so a failure reproduces.
    seed: u64,
    /// How many cases were generated before the run stopped (at `count` on a
    /// pass, or at the first failing case).
    generated_cases: u64,
    passed: bool,
    /// The first generated value that failed the property, or null on a pass.
    counterexample: ?u64,
};

/// Draw up to `count` deterministic u64 cases from `seed` and check `property`
/// against each. Stops at the first failure and records it. Pure and
/// reproducible: identical (seed, count, property) always yields the identical
/// Outcome.
pub fn forAllU64(seed: u64, count: u64, property: *const fn (u64) bool) Outcome {
    var g = gen.Generator.init(seed);
    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const draw = g.next();
        if (!property(draw)) {
            return .{
                .seed = seed,
                .generated_cases = i + 1,
                .passed = false,
                .counterexample = draw,
            };
        }
    }
    return .{
        .seed = seed,
        .generated_cases = count,
        .passed = true,
        .counterexample = null,
    };
}
