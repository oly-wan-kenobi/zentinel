# Error Codes

zentinel diagnostics should be compiler-like: direct, scoped, and actionable. Error codes make reports, tests, and autonomous debugging stable.

## Format

```text
ZNTL_<AREA>_<NAME>
```

Areas:

```text
CLI
CONFIG
ZIG
PROJECT
BACKEND
MUTATOR
SANDBOX
RUNNER
REPORT
CACHE
AI
DOCTEST
TASK
INTERNAL
```

## Core Error Codes

| Code | Phase | Meaning |
| --- | --- | --- |
| `ZNTL_CLI_UNKNOWN_COMMAND` | CLI | Command is not recognized. |
| `ZNTL_CLI_COMMAND_NOT_IMPLEMENTED` | CLI | Command is recognized from the roadmap but not implemented in the current phase. |
| `ZNTL_CLI_INVALID_OPTION` | CLI | Option is unknown, duplicated, or missing a value. |
| `ZNTL_CONFIG_NOT_FOUND` | Config | Config path does not exist. |
| `ZNTL_CONFIG_PARSE_ERROR` | Config | Config syntax is invalid. |
| `ZNTL_CONFIG_UNKNOWN_KEY` | Config | Config contains an unsupported section or key. |
| `ZNTL_CONFIG_INVALID_VALUE` | Config | Config value has wrong type or unsupported enum value. |
| `ZNTL_CONFIG_INVALID_COMMAND` | Config | Configured test command cannot be parsed by zentinel's shell-free command grammar. |
| `ZNTL_CONFIG_EXPERIMENTAL_BACKEND` | Config | ZIR/AIR selected without explicit experimental opt-in. |
| `ZNTL_ZIG_NOT_FOUND` | Zig version | Zig executable could not be found. |
| `ZNTL_ZIG_UNSUPPORTED_VERSION` | Zig version | Discovered Zig version is not latest stable for this zentinel release. |
| `ZNTL_PROJECT_NO_SOURCES` | Project model | Include/exclude rules produce no source files. |
| `ZNTL_BACKEND_PARSE_ERROR` | Backend | Source could not be parsed or tokenized. |
| `ZNTL_BACKEND_SOURCE_MAPPING_FAILED` | Backend | Backend candidate lacks exact source mapping. |
| `ZNTL_MUTATOR_INVALID_CANDIDATE` | Mutator | Mutator generated a candidate violating its spec. |
| `ZNTL_SANDBOX_CREATE_FAILED` | Sandbox | Mutation workspace could not be created. |
| `ZNTL_SANDBOX_PATCH_MISMATCH` | Sandbox | Source at span does not match mutant original text. |
| `ZNTL_SANDBOX_PATCH_OUT_OF_RANGE` | Sandbox | Mutant span is outside source bounds. |
| `ZNTL_RUNNER_BASELINE_FAILED` | Runner | Baseline tests failed before mutation execution. |
| `ZNTL_RUNNER_TIMEOUT` | Runner | Test command exceeded timeout. |
| `ZNTL_RUNNER_COMMAND_FAILED` | Runner | Process failed in a non-mutant baseline context. |
| `ZNTL_REPORT_SCHEMA_ERROR` | Report | Report object cannot satisfy schema. |
| `ZNTL_CACHE_KEY_MISMATCH` | Cache | Cache entry does not match current deterministic inputs. |
| `ZNTL_AI_DISABLED` | AI | AI command requested while AI is disabled. |
| `ZNTL_AI_PROVIDER_NOT_ALLOWED` | AI | Requested AI provider is not allowed by config, policy, or command options. |
| `ZNTL_AI_REPORT_NOT_FOUND` | AI | AI command requires a deterministic report path that does not exist. |
| `ZNTL_AI_TARGET_NOT_FOUND` | AI | AI command target, such as a mutant ref, does not resolve in the selected report. |
| `ZNTL_AI_RESPONSE_INVALID` | AI | Provider response failed schema validation. |
| `ZNTL_DOCTEST_CASE_NOT_FOUND` | Doctest | Doctest case ref does not resolve to exactly one case in the selected report or extraction. |
| `ZNTL_DOCTEST_DOC_NOT_FOUND` | Doctest | Doctest suggestion target is not an existing project-relative documentation path. |
| `ZNTL_DOCTEST_INVALID_BLOCK` | Doctest | Doctest block grouping or metadata is invalid. |
| `ZNTL_DOCTEST_UNSUPPORTED_TAG` | Doctest | Executable doctest fence uses an unsupported tag. |
| `ZNTL_DOCTEST_COMMAND_REJECTED` | Doctest | CLI doctest command is not allowed by doctest policy. |
| `ZNTL_DOCTEST_SNAPSHOT_MISMATCH` | Doctest | Actual doctest output did not match expected output. |
| `ZNTL_TASK_STATE_INVALID` | Task system | Queue/status metadata is inconsistent. |
| `ZNTL_INTERNAL_INVARIANT` | Internal | zentinel violated an internal invariant. |

## Diagnostic Shape

Human-readable diagnostics should follow:

```text
error[ZNTL_CONFIG_UNKNOWN_KEY]: unsupported config key
  --> zentinel.toml:12:1
   |
12 | unknown = true
   | ^^^^^^^ this key is not part of [project]
help: remove the key or add support through a documented config change
```

JSON diagnostics should include:

```json
{
  "code": "ZNTL_CONFIG_UNKNOWN_KEY",
  "phase": "config",
  "message": "unsupported config key",
  "path": "zentinel.toml",
  "line": 12,
  "column": 1,
  "help": "remove the key or add support through a documented config change"
}
```

## Stability

Error codes are public contract once they appear in reports or snapshots. Renaming an error code requires:

- documentation update
- snapshot update
- migration note
- compatibility decision in the active task
