#!/usr/bin/env bash
# Benchmark smoke entrypoint (tasks/052). Verifies the documented CI smoke
# budgets are present, runs the deterministic performance benchmark suite, and
# emits the machine-readable, normalized benchmark output for trend comparison.
# Intended to complete within the "benchmark smoke runtime" budget in
# docs/PERFORMANCE_STRATEGY.md (120 seconds). Fails closed on any error.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 scripts/check_perf_budgets.py
zig build test

echo "=== benchmark output (zentinel.benchmark.v1) ==="
cat test/fixtures/performance/benchmark.json
echo
