#!/usr/bin/env python3
"""Pipeline artifact CI check (task 064).

Validate pipeline artifact metadata with the project-owned subset validator in
``scripts/validate_task_system.py``. This is the canonical, network-free,
deterministic CI step that keeps committed pipeline evidence (handoffs, active
locks, context packets) schema-valid and task-scoped across fresh agent
sessions. Diagnostics use project-relative paths and are emitted in sorted order
so CI output is stable for snapshots.

Modes::

    check_pipeline_artifacts.py              validate the committed
                                             artifacts/pipeline tree, then
                                             self-test the CI fixtures
    check_pipeline_artifacts.py --real-tree  validate only the committed tree
    check_pipeline_artifacts.py --self-test  validate only the CI fixtures:
                                             ``valid/`` must be clean and every
                                             ``invalid/<case>`` must be rejected

Exit status: ``0`` all checks passed, ``1`` at least one violation or self-test
failure, ``2`` usage error.
"""
from __future__ import annotations

import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent
ROOT = SCRIPTS_DIR.parent
sys.path.insert(0, str(SCRIPTS_DIR))

import validate_task_system as vts  # noqa: E402

CI_FIXTURES = ROOT / "test" / "fixtures" / "pipeline" / "ci_artifacts"


def check_real_tree() -> list[str]:
    """Validate the committed ``artifacts/pipeline`` tree.

    Returns a sorted list of project-relative violations (empty when clean)."""
    return sorted(vts.validate_pipeline_artifact_tree(ROOT))


def check_self_test() -> list[str]:
    """Self-test the validator against the CI fixtures.

    ``valid/`` must pass with no violations and every ``invalid/<case>`` must be
    rejected by at least one deterministic violation. Returns a sorted list of
    problems (empty when the validator behaves correctly)."""
    problems: list[str] = []
    if not CI_FIXTURES.is_dir():
        return [f"missing CI fixture root {CI_FIXTURES.relative_to(ROOT)}"]

    valid_root = CI_FIXTURES / "valid"
    if not valid_root.is_dir():
        problems.append(f"missing {valid_root.relative_to(ROOT)}")
    else:
        for violation in sorted(vts.validate_pipeline_artifact_tree(valid_root)):
            problems.append(f"valid fixture must pass but reported: {violation}")

    invalid_root = CI_FIXTURES / "invalid"
    if not invalid_root.is_dir():
        problems.append(f"missing {invalid_root.relative_to(ROOT)}")
    else:
        cases = sorted(p for p in invalid_root.iterdir() if p.is_dir())
        if not cases:
            problems.append(f"{invalid_root.relative_to(ROOT)} has no invalid cases")
        for case in cases:
            if not vts.validate_pipeline_artifact_tree(case):
                problems.append(f"invalid fixture {case.name} must be rejected but passed")
    return sorted(problems)


def main(argv: list[str]) -> int:
    mode = "all"
    if len(argv) > 1:
        if len(argv) > 2 or argv[1] not in ("--real-tree", "--self-test"):
            sys.stderr.write("usage: check_pipeline_artifacts.py [--real-tree|--self-test]\n")
            return 2
        mode = argv[1][2:]

    failed = False

    if mode in ("all", "real-tree"):
        tree_violations = check_real_tree()
        if tree_violations:
            failed = True
            for violation in tree_violations:
                print(f"pipeline-artifacts: real-tree violation: {violation}")
            print(f"pipeline-artifacts: real tree FAILED with {len(tree_violations)} violation(s)")
        else:
            print("pipeline-artifacts: real tree OK (artifacts/pipeline)")

    if mode in ("all", "self-test"):
        problems = check_self_test()
        if problems:
            failed = True
            for problem in problems:
                print(f"pipeline-artifacts: self-test problem: {problem}")
            print(f"pipeline-artifacts: self-test FAILED with {len(problems)} problem(s)")
        else:
            print("pipeline-artifacts: self-test OK (valid fixture clean; invalid fixtures rejected)")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
