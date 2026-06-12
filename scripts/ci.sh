#!/usr/bin/env bash
# Canonical in-repository CI entrypoint.
#
# Runs the required deterministic verification stages in order, then an
# advisory dogfood stage. Network-independent: it never requires a remote AI
# provider.
#
# Usage:
#   scripts/ci.sh           run all required deterministic stages, then dogfood
#   scripts/ci.sh --list    print the stage names in order without running them
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

# Required deterministic stages, in order. Each is network-independent.
stage_names=(
  "format_check"
  "build"
  "unit_tests"
  "advisory_dogfood"
)

if [[ "${1:-}" == "--list" ]]; then
  for name in "${stage_names[@]}"; do
    printf '%s\n' "$name"
  done
  exit 0
fi

# Stage 1: format check (never modifies files).
printf '== ci stage: format_check ==\n'
zig fmt --check src test build.zig

# Stage 2: build the binary.
printf '== ci stage: build ==\n'
zig build

# Stage 3: unit + property + doctest tests.
printf '== ci stage: unit_tests ==\n'
zig build test

# Stage 4: advisory dogfood. Advisory only: a non-zero status is reviewed
# (survivors are not score-driven CI failures); only infrastructure or
# deterministic-core errors should block. Runs the fixture dogfood by default to
# keep CI fast and deterministic; selected production-source dogfood is opt-in
# via scripts/dogfood-production.sh.
printf '== ci stage: advisory_dogfood ==\n'
# Suppress only the dogfood STDOUT; let its STDERR through. dogfood.sh does NOT
# pass --fail-on-survivors, so mutation survivors exit 0 -- a non-zero status is
# therefore always an infrastructure/deterministic-core error (a `zig build`
# failure, a binary crash, or a ZNTL_ runtime error), never a survivor.
# Redirecting stderr to /dev/null as well would hide that real cause and
# wrongly blame survivors.
if ! scripts/dogfood.sh >/dev/null; then
  printf 'advisory dogfood exited non-zero: infrastructure/deterministic-core error (survivors exit 0 without --fail-on-survivors) -- inspect the dogfood stderr above\n' >&2
fi

printf 'ci: all required deterministic stages passed\n'
