#!/usr/bin/env python3
"""Ensure public contribution guidance matches the release gates."""

from __future__ import annotations

import sys
from pathlib import Path


REQUIRED_WORKFLOW_GATES = (
    "zig build quality",
    "python3 scripts/check_build_steps.py --skip quality --skip release-check",
    "python3 scripts/check_build_steps.py --skip quality --skip release-check --skip-interactive",
    "python3 scripts/visual_repeat_check.py --count 4",
    "python3 scripts/interactive_example_smoke.py",
    "python3 scripts/resize_smoke.py",
    "python3 scripts/mouse_alignment_smoke.py",
    "python3 scripts/check_accessibility_metadata.py",
    "python3 scripts/check_example_coverage.py",
    "python3 scripts/check_mouse_hit_coverage.py",
    "python3 scripts/check_owned_allocation_patterns.py",
    "python3 scripts/check_widget_owner_casts.py",
    "zig build release-check",
)

REQUIRED_PR_GATES = (
    "zig fmt --check src/ examples/ build.zig",
    "zig build quality",
    "python3 scripts/interactive_example_smoke.py",
    "python3 scripts/resize_smoke.py --no-build",
    "python3 scripts/mouse_alignment_smoke.py --no-build",
    "python3 scripts/visual_repeat_check.py --count 4",
    "python3 scripts/check_accessibility_metadata.py",
    "python3 scripts/check_example_coverage.py",
    "python3 scripts/check_mouse_hit_coverage.py",
    "python3 scripts/check_owned_allocation_patterns.py",
    "python3 scripts/check_widget_owner_casts.py",
    "zig build release-check",
)

REQUIRED_STABILITY_GATES = REQUIRED_PR_GATES + (
    "python3 scripts/check_contribution_gates.py",
)

REQUIRED_RELEASE_VERIFY_GATES = (
    '"contribution gates", ("python3", "scripts/check_contribution_gates.py")',
    '"accessibility metadata", ("python3", "scripts/check_accessibility_metadata.py")',
    '"example coverage", ("python3", "scripts/check_example_coverage.py")',
    '"mouse hit coverage", ("python3", "scripts/check_mouse_hit_coverage.py")',
    '"owned allocation patterns", ("python3", "scripts/check_owned_allocation_patterns.py")',
    '"mouse alignment PTY smoke", ("python3", "scripts/mouse_alignment_smoke.py", "--no-build")',
    '"widget owner casts", ("python3", "scripts/check_widget_owner_casts.py")',
)

REQUIRED_CONTRIBUTING_GATES = (
    "zig fmt --check src/ examples/ build.zig",
    "zig build quality",
    "python3 scripts/interactive_example_smoke.py",
    "python3 scripts/resize_smoke.py --no-build",
    "python3 scripts/mouse_alignment_smoke.py --no-build",
    "python3 scripts/visual_repeat_check.py --count 4",
    "python3 scripts/check_accessibility_metadata.py",
    "python3 scripts/check_example_coverage.py",
    "python3 scripts/check_mouse_hit_coverage.py",
    "python3 scripts/check_owned_allocation_patterns.py",
    "python3 scripts/check_widget_owner_casts.py",
    "zig build release-check",
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def require_contains(path: Path, markers: tuple[str, ...]) -> list[str]:
    text = path.read_text(encoding="utf-8")
    return [marker for marker in markers if marker not in text]


def workflow_job_block(workflow_text: str, job_name: str) -> str:
    marker = f"  {job_name}:"
    start = workflow_text.find(marker)
    if start == -1:
        raise RuntimeError(f".github/workflows/build.yaml missing job: {job_name}")

    next_job = next_workflow_job_index(workflow_text, start + len(marker))
    return workflow_text[start:next_job]


def next_workflow_job_index(workflow_text: str, start: int) -> int:
    for index in range(start, len(workflow_text)):
        if workflow_text[index] != "\n":
            continue
        line_start = index + 1
        if workflow_text.startswith("  ", line_start) and not workflow_text.startswith("    ", line_start):
            line_end = workflow_text.find("\n", line_start)
            if line_end == -1:
                line_end = len(workflow_text)
            line = workflow_text[line_start:line_end]
            if line.endswith(":"):
                return index
    return len(workflow_text)


def validate_release_verify_job(root: Path) -> list[str]:
    workflow = root / ".github" / "workflows" / "build.yaml"
    text = workflow.read_text(encoding="utf-8")
    try:
        block = workflow_job_block(text, "release-verify")
    except RuntimeError as err:
        return [str(err)]

    errors: list[str] = []
    if "\n    if:" in block:
        errors.append(".github/workflows/build.yaml: release-verify must not be job-level gated; it must run on PRs, main pushes, and tags")
    if "run: zig build release-check" not in block:
        errors.append(".github/workflows/build.yaml: release-verify must run `zig build release-check`")
    return errors


def main() -> int:
    root = repo_root()
    checks = (
        (root / ".github" / "workflows" / "build.yaml", REQUIRED_WORKFLOW_GATES),
        (root / ".github" / "PULL_REQUEST_TEMPLATE.md", REQUIRED_PR_GATES),
        (root / "CONTRIBUTING.md", REQUIRED_CONTRIBUTING_GATES),
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

    for error in validate_release_verify_job(root):
        failed = True
        sys.stderr.write(error + "\n")

    if failed:
        return 1

    print("checked contribution gate metadata")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
