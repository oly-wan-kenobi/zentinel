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

    /// A value in `[lo, hi]` (inclusive). `lo <= hi` is required.
    pub fn intRange(self: *Generator, lo: i64, hi: i64) i64 {
        std.debug.assert(lo <= hi);
        const span: u64 = @intCast(hi - lo + 1);
        return lo + @as(i64, @intCast(self.next() % span));
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
