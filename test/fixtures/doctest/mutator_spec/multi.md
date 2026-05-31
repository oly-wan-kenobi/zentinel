# multiple before/after pairs

```zig before
fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```zig after
fn add(a: i32, b: i32) i32 {
    return a - b;
}
```

Some unrelated prose between the two documented transformations.

```zig before
fn flag() bool {
    return true;
}
```

```zig after
fn flag() bool {
    return false;
}
```
