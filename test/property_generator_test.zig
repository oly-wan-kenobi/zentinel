const std = @import("std");
const zentinel = @import("zentinel");
const gen = zentinel.property.generator;
const support = @import("support/property.zig");

// ---------------------------------------------------------------------------
// 1. Determinism: the same seed emits the same generated case sequence.
// ---------------------------------------------------------------------------
test "same seed emits the same generated case sequence" {
    var g1 = gen.Generator.init(0xC0FFEE);
    var g2 = gen.Generator.init(0xC0FFEE);
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        try std.testing.expectEqual(g1.next(), g2.next());
    }

    // A different seed must diverge within a short prefix (not a constant stream).
    var same = gen.Generator.init(0xC0FFEE);
    var other = gen.Generator.init(0xC0FFEF);
    var diverged = false;
    i = 0;
    while (i < 16) : (i += 1) {
        if (same.next() != other.next()) {
            diverged = true;
            break;
        }
    }
    try std.testing.expect(diverged);
}

// The Generator's draw helpers (intRange/boolean/bytes) are public API but had no
// caller or test; intRange also carried a latent overflow -- `hi - lo + 1` and the
// i64 @intCast of the modulo panic for a range spanning more than half the i64
// domain. These pin the bounds (including the full i64 width) and determinism.
test "Generator.intRange stays in bounds for normal, point, and full-width ranges" {
    // Normal range: every draw is within [lo, hi], including negative lo.
    var g = gen.Generator.init(0x123456789ABCDEF);
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const v = g.intRange(-5, 5);
        try std.testing.expect(v >= -5 and v <= 5);
    }

    // A point range lo == hi returns exactly that value.
    var gp = gen.Generator.init(7);
    try std.testing.expectEqual(@as(i64, 42), gp.intRange(42, 42));

    // The full i64 width must neither overflow `hi - lo + 1` nor panic an i64
    // @intCast on the modulo result -- the latent bug. Pre-fix this panics; post-fix
    // every draw is a valid i64 in range.
    var gf = gen.Generator.init(0xDEADBEEF);
    var j: usize = 0;
    while (j < 200) : (j += 1) {
        const v = gf.intRange(std.math.minInt(i64), std.math.maxInt(i64));
        try std.testing.expect(v >= std.math.minInt(i64) and v <= std.math.maxInt(i64));
    }
}

test "Generator.boolean and bytes are deterministic and exercise their range" {
    // boolean(): both values occur over many draws (not a stuck stream).
    var g = gen.Generator.init(0xABCDEF);
    var seen_true = false;
    var seen_false = false;
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        if (g.boolean()) {
            seen_true = true;
        } else {
            seen_false = true;
        }
    }
    try std.testing.expect(seen_true and seen_false);

    // bytes(): a fixed seed fills the whole buffer identically; a different seed
    // produces a different fill (the stream is actually consumed, not left zeroed).
    var a_buf: [37]u8 = undefined;
    var b_buf: [37]u8 = undefined;
    var c_buf: [37]u8 = undefined;
    var ga = gen.Generator.init(0x2024);
    var gb = gen.Generator.init(0x2024);
    var gc = gen.Generator.init(0x2025);
    ga.bytes(&a_buf);
    gb.bytes(&b_buf);
    gc.bytes(&c_buf);
    try std.testing.expectEqualSlices(u8, &a_buf, &b_buf);
    try std.testing.expect(!std.mem.eql(u8, &a_buf, &c_buf));
}

// The support helper runs a property over a seeded stream and records the seed,
// the generated case count, and a counterexample on failure — deterministically.
test "property support helper records seed and generated case count deterministically" {
    const run_a = support.forAllU64(99, 64, struct {
        fn f(_: u64) bool {
            return true;
        }
    }.f);
    try std.testing.expect(run_a.passed);
    try std.testing.expectEqual(@as(u64, 99), run_a.seed);
    try std.testing.expectEqual(@as(u64, 64), run_a.generated_cases);
    try std.testing.expectEqual(@as(?u64, null), run_a.counterexample);

    // A property that rejects odd draws stops at the first failing case and
    // records it; the same seed reproduces the same counterexample exactly.
    const fail_1 = support.forAllU64(99, 64, struct {
        fn f(x: u64) bool {
            return x % 2 == 0;
        }
    }.f);
    const fail_2 = support.forAllU64(99, 64, struct {
        fn f(x: u64) bool {
            return x % 2 == 0;
        }
    }.f);
    try std.testing.expect(!fail_1.passed);
    try std.testing.expect(fail_1.counterexample != null);
    try std.testing.expectEqual(fail_1.counterexample, fail_2.counterexample);
    try std.testing.expectEqual(fail_1.generated_cases, fail_2.generated_cases);
}
