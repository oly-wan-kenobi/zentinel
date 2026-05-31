# Unknown key rejection

An unknown config key must be rejected.

```toml config_fail
[project]
bogus = "x"
```

```text output contains
ZNTL_CONFIG_UNKNOWN_KEY
```
