#!/usr/bin/env python3
"""Ensure public contribution guidance matches the release gates."""

from __future__ import annotations

import sys
from pathlib import Path


REQUIRED_WORKFLOW_GATES = (
    "zig build quality",
    "python3 scripts/check_build_steps.py --skip quality --skip release-check",
    "python3 scripts/visual_repeat_check.py --count 4",
    "python3 scripts/interactive_example_smoke.py",
    "python3 scripts/resize_smoke.py",
    "zig build release-check",
)

REQUIRED_PR_GATES = (
    "zig fmt --check src/ examples/ build.zig",
    "zig build quality",
    "python3 scripts/interactive_example_smoke.py",
    "python3 scripts/resize_smoke.py --no-build",
    "python3 scripts/visual_repeat_check.py --count 4",
    "zig build release-check",
)

REQUIRED_STABILITY_GATES = REQUIRED_PR_GATES + (
    "python3 scripts/check_contribution_gates.py",
)

REQUIRED_RELEASE_VERIFY_GATES = (
    '"contribution gates", ("python3", "scripts/check_contribution_gates.py")',
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def require_contains(path: Path, markers: tuple[str, ...]) -> list[str]:
    text = path.read_text(encoding="utf-8")
    return [marker for marker in markers if marker not in text]


def main() -> int:
    root = repo_root()
    checks = (
        (root / ".github" / "workflows" / "build.yaml", REQUIRED_WORKFLOW_GATES),
        (root / ".github" / "PULL_REQUEST_TEMPLATE.md", REQUIRED_PR_GATES),
        (root / "docs" / "STABILITY.md", REQUIRED_STABILITY_GATES),
        (root / "scripts" / "release_verify.py", REQUIRED_RELEASE_VERIFY_GATES),
    )

    failed = False
    for path, markers in checks:
        missing = require_contains(path, markers)
        if missing:
            failed = True
            sys.stderr.write(f"{path.relative_to(root)} missing gate marker(s):\n")
            for marker in missing:
                sys.stderr.write(f"  - {marker}\n")

    if failed:
        return 1

    print("checked contribution gate metadata")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
