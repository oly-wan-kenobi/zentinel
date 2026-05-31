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

The gate verifies behavior rather than self-authored claims (task 110): it
RECOMPUTES the repeated-run comparison from the archived reports (the Python port
of src/report.zig normalizeForComparison) instead of trusting the manifest's
`normalized_equal` boolean, requires every verified_by check and survivor
evidence to be a real on-disk artifact (a fabricated path or prose evidence is
rejected), and -- for the real manifest in main() -- actually EXECUTES the
script-type verified_by checks. Zig-test verified_by entries must be real test
entrypoints and are executed by the CI unit_tests stage.

Deterministic and network-free; diagnostics use project-relative paths and are
sorted. This stage runs in scripts/ci.sh before task 060 release acceptance.

Exit status: 0 the gate passed, 1 a violation or self-test failure.
"""
from __future__ import annotations

import json
import subprocess
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


def _normalize_report(obj: object) -> object:
    """Mirror src/report.zig normalizeForComparison: drop the documented
    observation metadata (run id, started_at, every duration_ms) so two reports
    from repeated runs over the same project compare structurally equal. This is
    the Python recomputation the gate runs instead of trusting a manifest boolean.
    """
    if isinstance(obj, dict):
        out: dict[str, object] = {}
        for k, val in obj.items():
            if k == "duration_ms":
                out[k] = "<duration>"
            elif k == "started_at":
                out[k] = "<started-at>"
            else:
                out[k] = _normalize_report(val)
        return out
    if isinstance(obj, list):
        return [_normalize_report(x) for x in obj]
    if isinstance(obj, str) and obj.startswith("run_"):
        return "<run-id>"
    return obj


def _reports_normalized_equal(rel_a: str, rel_b: str) -> bool:
    """Recompute the repeated-run comparison from the two archived reports."""
    try:
        a = json.loads((ROOT / rel_a).read_text(encoding="utf-8"))
        b = json.loads((ROOT / rel_b).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return _normalize_report(a) == _normalize_report(b)


def _execute_check(rel: str) -> int:
    """Actually run a script-type verified_by check; return its exit code (or a
    non-zero sentinel if it could not be launched)."""
    path = ROOT / rel
    cmd = ["python3", str(path)] if rel.endswith(".py") else ["bash", str(path)]
    try:
        return subprocess.run(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    except OSError:
        return 127


def validate_manifest(manifest: object, check_archives: bool = True, execute_checks: bool = False) -> list[str]:
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
            # A verified_by claim must reference a real check, not an unverified
            # string (task 110). The referenced path must exist; a .zig entry must
            # be a real test entrypoint (executed by the CI unit_tests stage); a
            # script entry is actually executed when execute_checks is set.
            if check_archives and isinstance(verified, str) and verified:
                if not (ROOT / verified).is_file():
                    v.append(f"verified_by check missing for gate {name}: {verified}")
                elif verified.endswith(".zig"):
                    if not (verified.startswith("test/") and verified.endswith("_test.zig")):
                        v.append(f"verified_by zig check is not a test entrypoint for gate {name}: {verified}")
                elif verified.endswith((".py", ".sh")):
                    if execute_checks:
                        code = _execute_check(verified)
                        if code != 0:
                            v.append(f"verified_by check failed (exit {code}) for gate {name}: {verified}")
                else:
                    v.append(f"verified_by check is not an executable script or test entrypoint for gate {name}: {verified}")
    for rg in REQUIRED_GATES:
        if rg not in seen:
            v.append(f"required gate {rg} is missing")

    rc = manifest.get("repeated_comparison")
    if not isinstance(rc, dict) or rc.get("normalized_equal") is not True:
        v.append("repeated dogfood comparison is not deterministic")
    elif check_archives:
        run_a = rc.get("run_a")
        run_b = rc.get("run_b")
        missing = False
        for key in ("run_a", "run_b"):
            p = rc.get(key)
            if not (isinstance(p, str) and p and (ROOT / p).is_file()):
                v.append(f"archived dogfood run missing: {p}")
                missing = True
        # Recompute the normalized comparison from the archived reports instead of
        # trusting `normalized_equal` (task 110): a manifest asserting determinism
        # whose reports are not actually normalized-equal is rejected.
        if not missing and isinstance(run_a, str) and isinstance(run_b, str):
            if not _reports_normalized_equal(run_a, run_b):
                v.append("repeated_comparison.normalized_equal is true but the archived reports are not normalized-equal (recomputed)")

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
                # The resolution evidence must be an archived artifact, not an
                # arbitrary string (task 110): a survivor "resolved" by prose is
                # rejected.
                elif check_archives and not (isinstance(sv.get("evidence"), str) and (ROOT / sv["evidence"]).is_file()):
                    v.append(f"protected survivor evidence is not an archived file: {sv.get('mutant_id')}")
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
        # The real manifest is validated with execute_checks=True so the
        # script-type verified_by checks are actually run (not merely named) and
        # the repeated-run comparison is recomputed from the archived reports.
        violations = validate_manifest(json.loads(DEFAULT_MANIFEST.read_text(encoding="utf-8")), check_archives=True, execute_checks=True)
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
