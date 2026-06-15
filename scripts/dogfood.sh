#!/usr/bin/env bash
# Stage 1 dogfood: run zentinel over the mutation fixtures.
#
# Documented command:
#   scripts/dogfood.sh
#
# Runs the zentinel binary against test/fixtures/dogfood/sample using
# zentinel.dogfood.toml. Requires no network access and no AI. Production
# zentinel modules are not mutated yet — only the fixture sources are.
#
# The deterministic report is archived under:
#   test/fixtures/dogfood/sample/zig-out/zentinel-dogfood/report.json
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fixture_root="test/fixtures/dogfood/sample"

# Build the binary, then run the dogfood mutation pass over the fixtures. The
# config sets project.root to the fixture, so no --root flag is needed.
zig build
./zig-out/bin/zentinel --config zentinel.dogfood.toml run "$@"

echo "dogfood report: $fixture_root/zig-out/zentinel-dogfood/report.json"
