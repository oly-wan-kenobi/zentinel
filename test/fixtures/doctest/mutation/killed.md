# killed documentation mutant

A strong doctest whose assertion catches the arithmetic mutation.

```zig test
const std = @import("std");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add is correct" {
    try std.testing.expect(add(2, 3) == 5);
}
```
