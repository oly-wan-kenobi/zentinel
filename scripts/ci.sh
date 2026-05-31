#!/usr/bin/env bash
# Canonical in-repository CI entrypoint (task 059).
#
# Runs the required deterministic verification stages from
# docs/VERIFICATION_PIPELINE.md in the documented order, then an advisory
# dogfood stage. Network-independent: it never requires a remote AI provider.
#
# This is NOT the final release dogfood gate; task 085 is the final release
# dogfood gate. Survivors from the advisory dogfood are reviewed, not treated as
# CI failures.
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
  "task_system_validation"
  "pipeline_artifact_validation"
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

# Stage 4: task-system validation (queue/status/schema/task consistency).
printf '== ci stage: task_system_validation ==\n'
python3 scripts/validate_task_system.py

# Stage 5: pipeline artifact validation. Validates the committed
# artifacts/pipeline tree (handoffs, active locks, context packets) against the
# project-owned pipeline schemas with deterministic, project-relative
# diagnostics, then self-tests the check against test/fixtures/pipeline/ci_artifacts.
# Deterministic and network-free; a violation blocks CI.
printf '== ci stage: pipeline_artifact_validation ==\n'
python3 scripts/check_pipeline_artifacts.py

# Stage 6: advisory dogfood. Advisory only: a non-zero status is reviewed
# (survivors are not score-driven CI failures); only infrastructure or
# deterministic-core errors should block. Runs the fixture dogfood by default to
# keep CI fast and deterministic; selected production-source dogfood is opt-in
# via scripts/dogfood-production.sh.
printf '== ci stage: advisory_dogfood ==\n'
if ! scripts/dogfood.sh >/dev/null 2>&1; then
  printf 'advisory dogfood reported a non-zero status (advisory; review survivors)\n' >&2
fi

printf 'ci: all required deterministic stages passed\n'
