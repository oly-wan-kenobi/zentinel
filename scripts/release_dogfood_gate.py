#!/usr/bin/env python3
"""Final release dogfood gate (task 085).

Validate the final dogfood release-evidence manifest and self-test it against
test/fixtures/release/{valid,invalid}. The gate passes only when every required
sub-gate -- fixture_dogfood, internal_module_dogfood, public_docs_doctest,
mutation_aware_doctest, doctest_survivor_ai, pipeline_artifact_validation, and
failure_recovery_validation -- passed with archived or test-verified evidence,
the repeated dogfood reports are deterministic, the protected scope has no
invalid mutants, and every protected survivor is resolved (fixed by a test or
recorded with deterministic equivalent-risk review evidence).

Deterministic and network-free; diagnostics use project-relative paths and are
sorted. This stage runs in scripts/ci.sh before task 060 release acceptance.

Exit status: 0 the gate passed, 1 a violation or self-test failure.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RELEASE_FIXTURES = ROOT / "test" / "fixtures" / "release"
DEFAULT_MANIFEST = RELEASE_FIXTURES / "valid" / "release_evidence.json"
SCHEMA_VERSION = "zentinel.release.dogfood_gate.v1"

REQUIRED_GATES = [
    "fixture_dogfood",
    "internal_module_dogfood",
    "public_docs_doctest",
    "mutation_aware_doctest",
    "doctest_survivor_ai",
    "pipeline_artifact_validation",
    "failure_recovery_validation",
]
SURVIVOR_RESOLUTIONS = {"fixed_by_test", "equivalent_risk_review"}


def validate_manifest(manifest: object, check_archives: bool = True) -> list[str]:
    """Return a sorted list of violations (empty = passing final dogfood gate)."""
    v: list[str] = []
    if not isinstance(manifest, dict):
        return ["manifest is not an object"]
    if manifest.get("schema_version") != SCHEMA_VERSION:
        v.append("schema_version is not " + SCHEMA_VERSION)
    if not manifest.get("task_id"):
        v.append("missing task_id")
    if manifest.get("status") != "passed":
        v.append("status is not passed")

    gates = manifest.get("gates")
    if not isinstance(gates, list):
        return sorted(v + ["gates is not an array"])
    seen = set()
    for g in gates:
        if not isinstance(g, dict):
            v.append("gate entry is not an object")
            continue
        name = g.get("name")
        seen.add(name)
        if g.get("required"):
            if g.get("status") != "passed":
                v.append(f"required gate {name} is not passed")
            report = g.get("report")
            verified = g.get("verified_by")
            if not report and not verified:
                v.append(f"required gate {name} has no archived report or verified_by evidence")
            if check_archives and isinstance(report, str) and report and not (ROOT / report).is_file():
                v.append(f"archived report missing for gate {name}: {report}")
    for rg in REQUIRED_GATES:
        if rg not in seen:
            v.append(f"required gate {rg} is missing")

    rc = manifest.get("repeated_comparison")
    if not isinstance(rc, dict) or rc.get("normalized_equal") is not True:
        v.append("repeated dogfood comparison is not deterministic")
    elif check_archives:
        for key in ("run_a", "run_b"):
            p = rc.get(key)
            if isinstance(p, str) and p and not (ROOT / p).is_file():
                v.append(f"archived dogfood run missing: {p}")

    ps = manifest.get("protected_scope")
    if not isinstance(ps, dict):
        v.append("missing protected_scope")
    else:
        if ps.get("invalid_mutants") != 0:
            v.append("protected scope has invalid mutants")
        survivors = ps.get("survivors")
        if isinstance(survivors, list):
            for sv in survivors:
                if (
                    not isinstance(sv, dict)
                    or sv.get("resolution") not in SURVIVOR_RESOLUTIONS
                    or not sv.get("evidence")
                ):
                    ident = sv.get("mutant_id") if isinstance(sv, dict) else sv
                    v.append(f"unresolved protected survivor: {ident}")
        else:
            v.append("protected_scope.survivors is not an array")
    return sorted(v)


def self_test() -> list[str]:
    """Every release manifest under valid/ must pass; every one under invalid/
    must be rejected. Non-manifest JSON files are ignored."""
    problems: list[str] = []
    valid_dir = RELEASE_FIXTURES / "valid"
    if valid_dir.is_dir():
        for fx in sorted(valid_dir.glob("*.json")):
            data = json.loads(fx.read_text(encoding="utf-8"))
            if not isinstance(data, dict) or data.get("schema_version") != SCHEMA_VERSION:
                continue
            violations = validate_manifest(data, check_archives=True)
            for viol in violations:
                problems.append(f"valid manifest {fx.name} must pass but reported: {viol}")
    invalid_dir = RELEASE_FIXTURES / "invalid"
    if invalid_dir.is_dir():
        for fx in sorted(invalid_dir.glob("*.json")):
            data = json.loads(fx.read_text(encoding="utf-8"))
            if not isinstance(data, dict) or data.get("schema_version") != SCHEMA_VERSION:
                continue
            if not validate_manifest(data, check_archives=True):
                problems.append(f"invalid manifest {fx.name} must be rejected but passed")
    return sorted(problems)


def main(argv: list[str]) -> int:
    failed = False

    if DEFAULT_MANIFEST.is_file():
        violations = validate_manifest(json.loads(DEFAULT_MANIFEST.read_text(encoding="utf-8")), check_archives=True)
        if violations:
            failed = True
            for viol in violations:
                print(f"release-gate: violation: {viol}")
            print(f"release-gate: final dogfood manifest FAILED with {len(violations)} violation(s)")
        else:
            print("release-gate: final dogfood manifest OK (archived deterministic evidence present)")
    else:
        failed = True
        print(f"release-gate: missing manifest {DEFAULT_MANIFEST.relative_to(ROOT)}")

    problems = self_test()
    if problems:
        failed = True
        for problem in problems:
            print(f"release-gate: self-test problem: {problem}")
        print(f"release-gate: self-test FAILED with {len(problems)} problem(s)")
    else:
        print("release-gate: self-test OK (valid manifest passes; invalid manifests rejected)")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
