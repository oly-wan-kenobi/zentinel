# Full config doctest

```toml config
[project]
name = "example"
root = "."
include = ["src/**/*.zig"]
exclude = [".zig-cache/**", "zig-out/**", "test/**"]

[zig]
version = "0.16.0"
modes = ["Debug"]

[backend]
default = "ast"
experimental = []

[mutators]
enabled = [
  "arithmetic_add_sub",
  "arithmetic_mul_div",
  "equality_swap",
  "comparison_boundary",
  "logical_and_or",
  "boolean_literal"
]

[test]
commands = ["zig build test"]
selection = "same_file_then_package"
timeout_ms = 30000
baseline_required = true

[run]
jobs = 1

[cache]
enabled = true
directory = ".zig-cache/zentinel"

[report]
formats = ["text", "json"]
output_dir = "zig-out/zentinel"

[ai]
enabled = false
provider = "disabled"
remote_allowed = false
source_context_lines = 4
redact_patterns = ["(?i)api[_-]?key", "(?i)token"]
```
