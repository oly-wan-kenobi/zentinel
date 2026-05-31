# Experimental backend rejection

An experimental backend without explicit opt-in must be rejected.

```toml config_fail
[backend]
default = "zir"
```

```text output contains
ZNTL_CONFIG_EXPERIMENTAL_BACKEND
```
