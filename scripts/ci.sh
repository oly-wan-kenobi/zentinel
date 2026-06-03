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
  "release_dogfood_gate"
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
# Suppress only the dogfood STDOUT; let its STDERR through. dogfood.sh does NOT
# pass --fail-on-survivors, so mutation survivors exit 0 -- a non-zero status is
# therefore always an infrastructure/deterministic-core error (a `zig build`
# failure, a binary crash, or a ZNTL_ runtime error), never a survivor. Redirecting
# stderr to /dev/null as well (the old behavior) hid that real cause, and the
# message wrongly blamed survivors (L33).
if ! scripts/dogfood.sh >/dev/null; then
  printf 'advisory dogfood exited non-zero: infrastructure/deterministic-core error (survivors exit 0 without --fail-on-survivors) -- inspect the dogfood stderr above\n' >&2
fi

# Stage 7: final release dogfood gate (task 085). Validates the archived
# deterministic dogfood evidence, the fixture/internal-module/public-doc-doctest/
# mutation-aware-doctest/doctest-survivor-AI/artifact/recovery sub-gates, and the
# resolved protected-scope survivors before task 060 release acceptance.
# Deterministic and network-free; a violation blocks CI.
printf '== ci stage: release_dogfood_gate ==\n'
python3 scripts/release_dogfood_gate.py

printf 'ci: all required deterministic stages passed\n'
