# normal doctest failure

If the unmutated doctest does not pass, mutation must not run for that case.

```zig test
const std = @import("std");

fn add(a: i32, b: i32) i32 {
    return a - b;
}

test "add is wrong on purpose" {
    try std.testing.expect(add(2, 3) == 5);
}
```
