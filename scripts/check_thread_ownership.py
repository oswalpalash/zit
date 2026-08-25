#!/usr/bin/env python3
"""Reject detached threads so spawned loops remain explicitly owned."""

from __future__ import annotations

import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def main() -> int:
    root = repo_root()
    failures: list[str] = []
    checked = 0

    for directory in ("src", "examples"):
        for path in sorted((root / directory).rglob("*.zig")):
            checked += 1
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if ".detach()" in line:
                    failures.append(f"{path.relative_to(root)}:{number}: detached worker thread")

    if failures:
        for failure in failures:
            sys.stderr.write(failure + "\n")
        return 1

    print(f"checked thread ownership in {checked} Zig file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
