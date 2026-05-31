# documentation drift

The documented `after` is not a transformation any stable mutator produces.

```zig before
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```zig after
fn add(a: i32, b: i32) i32 {
    return a * b;
}
```
