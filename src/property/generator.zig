// Layer: deterministic_core
//
// Minimal deterministic seeded generator for structural property tests
// (docs/PROPERTY_TEST_POLICY.md, task 062). A `Generator` is a pure splitmix64
// stream: the same seed always emits the same sequence, so a recorded failing
// seed reproduces the same generated cases byte-for-byte. No third-party
// dependency, no global state, no wall-clock or OS randomness.
const std = @import("std");

pub const Generator = struct {
    state: u64,

    pub fn init(seed: u64) Generator {
        return .{ .state = seed };
    }

    /// splitmix64: a fast, well-distributed, fully deterministic 64-bit stream.
    pub fn next(self: *Generator) u64 {
        self.state +%= 0x9E3779B97F4A7C15;
        var z = self.state;
        z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
        z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
        return z ^ (z >> 31);
    }

    /// A value in `[lo, hi]` (inclusive). `lo <= hi` is required. The inclusive span
    /// and the mapped draw are computed in u64 (via `@bitCast`) so a range spanning
    /// more than half the i64 domain -- up to the full `minInt(i64)..maxInt(i64)` --
    /// can neither overflow the `hi - lo + 1` intermediate nor panic an i64 `@intCast`
    /// on the modulo result (L39). A wrapped span of 0 means the full u64 domain.
    pub fn intRange(self: *Generator, lo: i64, hi: i64) i64 {
        std.debug.assert(lo <= hi);
        const lo_u: u64 = @bitCast(lo);
        const hi_u: u64 = @bitCast(hi);
        const span: u64 = (hi_u -% lo_u) +% 1;
        const offset: u64 = if (span == 0) self.next() else self.next() % span;
        return @bitCast(lo_u +% offset);
    }

    pub fn boolean(self: *Generator) bool {
        return (self.next() & 1) == 1;
    }

    /// Fill `out` with deterministic bytes from the stream.
    pub fn bytes(self: *Generator, out: []u8) void {
        var i: usize = 0;
        while (i < out.len) {
            var word = self.next();
            var k: usize = 0;
            while (k < 8 and i < out.len) : (k += 1) {
                out[i] = @truncate(word);
                word >>= 8;
                i += 1;
            }
        }
    }
};
