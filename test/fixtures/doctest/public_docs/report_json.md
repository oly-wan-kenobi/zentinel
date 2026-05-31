# Public report JSON doctest coverage

The canonical JSON report envelope is validated as a supported subset.

```bash cli
zentinel run --report json
```

```json expected subset
{
  "schema_version": "zentinel.report.v1",
  "run": {
    "status": "completed"
  }
}
```
