# mutation experiment report

A killed mutant, a survived mutant, and a skipped (no-assertion) case.

```zig test
const std = @import("std");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add is correct" {
    try std.testing.expect(add(2, 3) == 5);
}
```

```zig test
const std = @import("std");

fn nonneg(a: i32) bool {
    return a >= 0;
}

test "nonneg accepts a positive" {
    try std.testing.expect(nonneg(5));
}
```

```zig test
const std = @import("std");

fn noop(a: i32) i32 {
    return a + 1;
}

test "noop runs" {
    _ = noop(2);
}
```
