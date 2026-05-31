# Config fail with the wrong documented diagnostic

The config fails, but the documented diagnostic is wrong, so the case must fail.

```toml config_fail
[backend]
default = "zir"
```

```text output contains
ZNTL_CONFIG_UNKNOWN_KEY
```
