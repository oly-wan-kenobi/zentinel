# Public doctest AI JSON doctest coverage

The advisory doctest-suggest response is validated as a supported subset.

```bash cli
zentinel doctest suggest docs/CLI_SPEC.md --ai-provider stub --format json
```

```json expected subset
{
  "schema_version": "zentinel.ai.doctest.suggest.response.v1"
}
```
