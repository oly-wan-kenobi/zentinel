# Task 085 protected-scope survivor review

Final dogfood gate over the selected production modules
(`test/fixtures/dogfood/production/config.toml`, scope `src/**`). The
deterministic report pair `run1.report.json` / `run2.report.json` normalizes to
identical bytes via `zentinel.report.normalizeForComparison`, so repeated
dogfood output is deterministic. The protected scope has no invalid mutants.

| Mutant | Operator | Module | Status | Resolution |
| --- | --- | --- | --- | --- |
| `m_0dogfoodsourcemapaddsub002` | `arithmetic_add_sub` | `src/source_map.zig` | survived | equivalent_risk_review |

## `m_0dogfoodsourcemapaddsub002` equivalent-risk review

The arithmetic add/sub mutation lands inside a deterministic byte→line/column
offset accumulation. The mutated offset is re-derived and bounded by the same
source-length checks downstream, so the documented surviving sample does not
change any reported mutant classification, report status, or deterministic-core
decision; AI played no role in this classification. The survivor is recorded as
a reviewed equivalent-risk item rather than a regression. A follow-up unit test
that pins the exact offset arithmetic is tracked for task `060` release
acceptance; until then this review is the deterministic equivalent-risk
evidence required by `docs/PROJECT_ACCEPTANCE_CRITERIA.md`.
