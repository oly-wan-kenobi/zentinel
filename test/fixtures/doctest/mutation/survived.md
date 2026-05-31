# survived documentation mutant

A weak doctest: the boundary mutation is not caught by the chosen input.

```zig test
const std = @import("std");

fn nonneg(a: i32) bool {
    return a >= 0;
}

test "nonneg accepts a positive" {
    try std.testing.expect(nonneg(5));
}
```
