#!/usr/bin/env bash
# Initial advisory production dogfood: run zentinel over a small set
# of selected internal modules, deterministically and advisory-only.
#
# Documented command:
#   scripts/dogfood-production.sh [extra zentinel run args...]
#
# Uses test/fixtures/dogfood/production/config.toml (selected src modules,
# `zig build test`). No network access and no AI. Survivors are reviewed, not a
# failure. Reference deterministic reports are committed under
# test/fixtures/dogfood/production/run1.report.json and run2.report.json; the
# runtime report is written under zig-out/zentinel/dogfood-production/.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

config="test/fixtures/dogfood/production/config.toml"

zig build
# Advisory: never fail on ordinary survivors (no --fail-on-survivors).
./zig-out/bin/zentinel --config "$config" run --report json "$@"

echo "production dogfood report: zig-out/zentinel/dogfood-production/report.json"
echo "deterministic reference reports: test/fixtures/dogfood/production/run{1,2}.report.json"
