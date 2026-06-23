# Labeled selectable CLI doctests

Two CLI cases at distinct lines, each carrying an explicit `case:<label>` so a
`--case file:line:label` selector can be checked for label-suffix matching.

```bash cli case:alpha
zentinel version
```

```text output contains
zentinel
```

Some prose between the two cases.

```bash cli case:beta
zentinel --help
```

```text output contains
Usage
```
