# before without after

A `zig before` block with no matching `zig after` is an invalid grouping.

```zig before
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```
