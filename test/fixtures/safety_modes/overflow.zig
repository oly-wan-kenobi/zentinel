//! Debug-vs-ReleaseFast fixture (task 058).
//!
//! A `comparison_boundary` mutation that turns `acc < 255` into `acc <= 255`
//! makes `next(255)` evaluate `255 + 1`, which overflows `u8`. Under Debug and
//! ReleaseSafe the overflow safety check panics, so the mutant is killed; under
//! ReleaseFast the check is elided and the value wraps to 0, so the same mutant
//! survives. That status difference is a safety-mode effect (mode-dependent),
//! not a flaky test, and is recorded in the additive `result.mode_matrix`.
const std = @import("std");

pub fn next(acc: u8) u8 {
    if (acc < 255) return acc + 1;
    return acc;
}

test "next stays in range and saturates at the maximum" {
    try std.testing.expectEqual(@as(u8, 200), next(199));
    try std.testing.expectEqual(@as(u8, 255), next(255));
}
