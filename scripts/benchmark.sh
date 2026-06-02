#!/usr/bin/env bash
# Benchmark smoke entrypoint (tasks/052). Verifies the documented CI smoke budgets
# are present (check_perf_budgets.py), runs the deterministic performance benchmark
# suite (`zig build test`), and prints the committed, normalized benchmark snapshot
# (zentinel.benchmark.v1). The benchmark is deterministic by design -- a mock
# executor with duration_ms = 0 -- so this output is the suite's reference
# EQUIVALENCE result (cached == uncached, serial == parallel, cold == warm) pinned
# byte-for-byte by the snapshot test in `zig build test`, NOT a live wall-clock
# measurement or a timing-trend feed; treat it as a logic/smoke check. Intended to
# complete within the "benchmark smoke runtime" budget in docs/PERFORMANCE_STRATEGY.md
# (120 seconds). Fails closed on any error.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 scripts/check_perf_budgets.py
zig build test

echo "=== benchmark output (zentinel.benchmark.v1) ==="
cat test/fixtures/performance/benchmark.json
echo
