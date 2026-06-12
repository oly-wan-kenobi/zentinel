#!/usr/bin/env python3
"""Documentation check: prove docs/PERFORMANCE_STRATEGY.md records the
concrete initial numeric CI smoke budgets that later dogfood, doctest, and
benchmark CI tasks depend on. Reads the doc from a path argument (default the
working tree) so the failing-first state can be captured against an older
revision, e.g.:

    git show HEAD:docs/PERFORMANCE_STRATEGY.md | python3 scripts/check_perf_budgets.py -

Exits 0 when every required budget line is present, 1 otherwise.
"""
import sys
from pathlib import Path

REQUIRED = [
    "fixture dogfood runtime | 30 seconds",
    "selected production dogfood runtime | 180 seconds",
    "doctest runtime | 60 seconds",
    "benchmark smoke runtime | 120 seconds",
]


def main() -> int:
    arg = sys.argv[1] if len(sys.argv) > 1 else "docs/PERFORMANCE_STRATEGY.md"
    text = sys.stdin.read() if arg == "-" else Path(arg).read_text(encoding="utf-8")
    missing = [line for line in REQUIRED if line not in text]
    if missing:
        for line in missing:
            print(f"FAIL: missing CI smoke budget line: {line!r}")
        return 1
    print(f"PASS: all {len(REQUIRED)} CI smoke budgets present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
