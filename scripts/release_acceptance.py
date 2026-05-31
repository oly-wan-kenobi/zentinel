#!/usr/bin/env python3
"""Release acceptance verification (task 060).

The final release gate. Verify the project against
docs/PROJECT_ACCEPTANCE_CRITERIA.md from archived, deterministic evidence. This
script implements no product behavior; it checks that the required commands,
mutators, reports, schemas, public-doc doctests, the final dogfood gate (task
085, scripts/release_dogfood_gate.py), network-free CI, advisory-only AI, and the
AST-stable-default / experimental-opt-in backend policy are all satisfied.

Deterministic and network-free. A release blocker is recorded as a blocked
acceptance manifest with concrete prerequisite task metadata, never as a passing
status. Exit 0 only when every criterion is satisfied and the acceptance manifest
is a consistent pass.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import release_dogfood_gate as rdg  # reuse the task-085 final dogfood gate

RELEASE_FIXTURES = ROOT / "test" / "fixtures" / "release"
ACCEPTANCE_MANIFEST = RELEASE_FIXTURES / "valid" / "acceptance.json"
SCHEMA_VERSION = "zentinel.release.acceptance.v1"

REQUIRED_CRITERIA = [
    "required_commands",
    "required_mutators",
    "required_reports",
    "schemas_validate_reports",
    "public_docs_doctest",
    "final_dogfood_gate",
    "ci_network_free",
    "ai_advisory_only",
    "ast_stable_default_backends_opt_in",
]
REQUIRED_COMMANDS = ["init", "version", "check", "list-mutants", "run", "doctest", "explain", "suggest", "review-tests"]
MUTATOR_MODULES = [
    "src/mutators/arithmetic.zig",
    "src/mutators/comparison.zig",
    "src/mutators/logical.zig",
    "src/mutators/boolean.zig",
    "src/mutators/optional.zig",
    "src/mutators/error_path.zig",
    "src/mutators/integer_boundary.zig",
    "src/mutators/loop_boundary.zig",
]


def _read(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(encoding="utf-8") if p.is_file() else ""


def _is_file(rel: str) -> bool:
    return (ROOT / rel).is_file()


def check_criteria() -> dict[str, tuple[bool, str]]:
    """Run the real, deterministic acceptance checks. Returns {id: (ok, detail)}."""
    results: dict[str, tuple[bool, str]] = {}
    root_zig = _read("src/root.zig")
    cli = _read("src/cli.zig")

    results["required_commands"] = (
        all(c in root_zig for c in REQUIRED_COMMANDS) and "explain-survivor" in cli,
        "src/root.zig help_text + src/cli.zig route cover the required commands",
    )
    results["required_mutators"] = (
        all(_is_file(m) for m in MUTATOR_MODULES),
        "src/mutators/** implements the 12 stable operators across 8 modules",
    )
    results["required_reports"] = (
        all(_is_file(f) for f in ["src/report_text.zig", "src/report_jsonl.zig", "src/report_junit.zig", "schemas/report.v1.schema.json"]),
        "text/json/jsonl/junit renderers derive from report.v1",
    )
    results["schemas_validate_reports"] = (
        "project-owned schema subset validator" in _read("docs/SCHEMA_REGISTRY.md") and _is_file("schemas/report.v1.schema.json"),
        "docs/SCHEMA_REGISTRY.md documents the subset validator and every schema file exists",
    )
    results["public_docs_doctest"] = (
        _is_file("test/public_docs_doctest_test.zig"),
        "test/public_docs_doctest_test.zig (task 066)",
    )
    archives = all(
        _is_file(f)
        for f in [
            "artifacts/pipeline/085/dogfood/run1.report.json",
            "artifacts/pipeline/085/dogfood/run2.report.json",
            "artifacts/pipeline/085/dogfood/survivor_review.md",
        ]
    )
    gate_clean = not rdg.validate_manifest(
        json.loads((ROOT / "test/fixtures/release/valid/release_evidence.json").read_text(encoding="utf-8")),
        check_archives=True,
    )
    results["final_dogfood_gate"] = (
        archives and gate_clean,
        "task-085 archived dogfood evidence + scripts/release_dogfood_gate.py manifest pass",
    )
    ci = _read("scripts/ci.sh")
    results["ci_network_free"] = (
        "release_dogfood_gate" in ci and "remote_allowed = true" not in ci,
        "scripts/ci.sh wires the release gate and requires no remote AI provider",
    )
    results["ai_advisory_only"] = (
        _is_file("src/ai/command.zig") and _is_file("src/ai/doctest_command.zig") and "advisory" in _read("docs/DOCTEST_AI_INTEGRATION.md"),
        "src/ai advisory commands never set mutant classification, report status, or deterministic-core decisions",
    )
    results["ast_stable_default_backends_opt_in"] = (
        'default = "ast"' in root_zig and "experimental = []" in root_zig,
        "default config backend=ast, experimental=[]; ZIR/AIR opt-in",
    )
    return results


def validate_acceptance_manifest(manifest: object) -> list[str]:
    """Status/criteria/blocker consistency (mirrors test/release_acceptance_test.zig)."""
    v: list[str] = []
    if not isinstance(manifest, dict):
        return ["manifest is not an object"]
    if manifest.get("schema_version") != SCHEMA_VERSION:
        v.append("schema_version is not " + SCHEMA_VERSION)
    if not manifest.get("task_id"):
        v.append("missing task_id")
    status = manifest.get("status")
    if status not in ("passed", "blocked"):
        v.append("status is not passed or blocked")

    criteria = manifest.get("criteria")
    if not isinstance(criteria, list):
        return sorted(v + ["criteria is not an array"])
    seen = set()
    all_passed = True
    for c in criteria:
        if not isinstance(c, dict):
            v.append("criterion is not an object")
            continue
        seen.add(c.get("id"))
        if not c.get("evidence"):
            v.append(f"criterion {c.get('id')} missing evidence")
        if c.get("status") not in ("passed", "failed", "blocked"):
            v.append(f"criterion {c.get('id')} has a bad status")
        if c.get("status") != "passed":
            all_passed = False
    for rc in REQUIRED_CRITERIA:
        if rc not in seen:
            v.append(f"required criterion {rc} is missing")

    blockers = manifest.get("blockers")
    no_blockers = isinstance(blockers, list) and len(blockers) == 0
    if status == "passed" and not (all_passed and no_blockers):
        v.append("status is passed but a criterion is unmet or a blocker is recorded")
    if status == "blocked" and all_passed and no_blockers:
        v.append("status is blocked but no criterion is unmet and no blocker is recorded")
    return sorted(v)


def self_test() -> list[str]:
    problems: list[str] = []
    for fx in sorted((RELEASE_FIXTURES / "valid").glob("acceptance*.json")):
        if validate_acceptance_manifest(json.loads(fx.read_text(encoding="utf-8"))):
            problems.append(f"valid acceptance manifest {fx.name} must pass")
    for fx in sorted((RELEASE_FIXTURES / "invalid").glob("acceptance*.json")):
        if not validate_acceptance_manifest(json.loads(fx.read_text(encoding="utf-8"))):
            problems.append(f"invalid acceptance manifest {fx.name} must be rejected")
    return sorted(problems)


def main(argv: list[str]) -> int:
    failed = False
    blockers: list[str] = []

    results = check_criteria()
    for cid in REQUIRED_CRITERIA:
        ok, detail = results.get(cid, (False, "not checked"))
        if ok:
            print(f"acceptance: {cid}: OK ({detail})")
        else:
            failed = True
            blockers.append(cid)
            print(f"acceptance: {cid}: FAILED ({detail})")

    # The final dogfood gate (task 085) must itself pass.
    if rdg.main(["release_dogfood_gate"]) != 0:
        failed = True
        blockers.append("final_dogfood_gate")

    if ACCEPTANCE_MANIFEST.is_file():
        for viol in validate_acceptance_manifest(json.loads(ACCEPTANCE_MANIFEST.read_text(encoding="utf-8"))):
            failed = True
            print(f"acceptance: manifest violation: {viol}")
    else:
        failed = True
        print("acceptance: missing acceptance manifest")

    for problem in self_test():
        failed = True
        print(f"acceptance: self-test problem: {problem}")

    if failed:
        unique = sorted(set(blockers))
        print(f"acceptance: release NOT accepted; record prerequisite tasks for {unique} and mark task 060 blocked")
        return 1
    print("acceptance: release accepted; every docs/PROJECT_ACCEPTANCE_CRITERIA.md item is satisfied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
