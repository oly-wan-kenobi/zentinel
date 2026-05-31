# comparison_boundary

```zig before
fn lt(a: i32, b: i32) bool {
    return a < b;
}
```

```zig after
fn lt(a: i32, b: i32) bool {
    return a <= b;
}
```
