# Extraction fixture

This fixture exercises every supported grouped case type. The prose between
blocks is intentionally varied so that prose-invariance can be checked.

A CLI example with expected output groups into one `cli` case:

```bash cli
zentinel --help
```

```text output contains
zentinel - Zig-native mutation testing
```

A standalone config example is its own `config` case:

```toml config
[project]
name = "example"
```

A unit test example is its own `zig_test` case:

```zig test
const std = @import("std");

test "ok" {
    try std.testing.expect(true);
}
```

A mutation before/after pair groups into one `mutation` case:

```zig before
return a + b;
```

```zig after
return a - b;
```
