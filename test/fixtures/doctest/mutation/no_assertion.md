# no behavioral assertion

A doctest that runs but asserts nothing must be skipped before mutation.

```zig test
const std = @import("std");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add runs" {
    _ = add(2, 3);
}
```
