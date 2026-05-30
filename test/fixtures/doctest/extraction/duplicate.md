# Duplicate unlabeled cases

Two identical unlabeled `zig test` cases in one file are ambiguous and must be
rejected, not given occurrence-based identifiers.

```zig test
test "dup" {
    try @import("std").testing.expect(true);
}
```

Some unrelated prose between the two identical examples.

```zig test
test "dup" {
    try @import("std").testing.expect(true);
}
```
