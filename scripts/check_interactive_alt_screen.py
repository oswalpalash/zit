#!/usr/bin/env python3
"""Ensure interactive examples use the alternate screen buffer."""

from __future__ import annotations

import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def main() -> int:
    root = repo_root()
    failures: list[str] = []
    checked = 0

    for path in sorted((root / "examples").rglob("*.zig")):
        if "benchmarks" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        if "initInteractive(" not in text:
            continue
        checked += 1
        missing: list[str] = []
        if ".enterAlternateScreen()" not in text:
            missing.append("enterAlternateScreen")
        if ".exitAlternateScreen()" not in text:
            missing.append("exitAlternateScreen")
        if missing:
            failures.append(f"{path.relative_to(root)} missing {', '.join(missing)}")

    if failures:
        sys.stderr.write("interactive examples must render inside the alternate screen:\n")
        for failure in failures:
            sys.stderr.write(f"  - {failure}\n")
        return 1

    print(f"checked {checked} interactive example(s) for alternate-screen setup")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
