# Parser fixture

A realistic mix of a doctest block, a documentation-only block, and prose.

```zig test
const std = @import("std");

test "fixture" {
    try std.testing.expect(2 + 2 == 4);
}
```

Plain prose between blocks.

```bash cli case:version
zentinel version
```

A documentation-only block that must stay documentation-only:

```python
print("not a doctest")
```
