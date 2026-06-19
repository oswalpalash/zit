#!/usr/bin/env python3
"""Require public examples to restore terminal state they enable."""

from __future__ import annotations

import sys
from pathlib import Path


PAIRS = (
    ("enterAlternateScreen", "exitAlternateScreen"),
    ("enableRawMode", "disableRawMode"),
    ("enableMouse", "disableMouse"),
    ("hideCursor", "showCursor"),
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def iter_example_sources(root: Path) -> list[Path]:
    return sorted((root / "examples").rglob("*.zig"))


def main() -> int:
    root = repo_root()
    failures: list[str] = []
    checked = 0

    for path in iter_example_sources(root):
        if "benchmarks" in path.parts:
            continue

        text = path.read_text(encoding="utf-8")
        if "initInteractive(" not in text:
            continue

        checked += 1
        rel = path.relative_to(root)
        for setup, cleanup in PAIRS:
            setup_call = f".{setup}("
            cleanup_call = f".{cleanup}("
            setup_index = text.find(setup_call)
            cleanup_index = text.find(cleanup_call)
            setup_present = setup_index >= 0
            cleanup_present = cleanup_index >= 0
            if setup_present and not cleanup_present:
                failures.append(f"{rel}: calls {setup} without {cleanup}")
            if cleanup_present and not setup_present:
                failures.append(f"{rel}: calls {cleanup} without {setup}")
            if setup_present and cleanup_present:
                if cleanup_index < setup_index:
                    failures.append(f"{rel}: calls {cleanup} before {setup}")
                elif "defer" not in text[setup_index:cleanup_index]:
                    failures.append(f"{rel}: restores {cleanup} without deferring it after {setup}")

    if failures:
        sys.stderr.write("interactive examples must restore terminal state they enable:\n")
        for failure in failures:
            sys.stderr.write(f"  - {failure}\n")
        return 1

    print(f"checked {checked} interactive example(s) for terminal-state cleanup symmetry")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
