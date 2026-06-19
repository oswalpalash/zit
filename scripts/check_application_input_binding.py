#!/usr/bin/env python3
"""Require Application-based examples to use Application-owned input polling."""

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
        has_application = "Application.init" in text or "Application.initWithMemoryManager" in text
        if not has_application or "InputHandler.init" not in text:
            continue

        checked += 1
        rel = path.relative_to(root)
        if ".bindInput(" not in text:
            failures.append(f"{rel}: initializes Application and InputHandler without bindInput")
        if ".pollInputOnce(" not in text:
            failures.append(f"{rel}: initializes Application and InputHandler without pollInputOnce")
        if ".pollEvent(" in text:
            failures.append(f"{rel}: bypasses Application input binding with direct pollEvent")

    if failures:
        sys.stderr.write("Application-based interactive examples must use bound input polling:\n")
        for failure in failures:
            sys.stderr.write(f"  - {failure}\n")
        return 1

    print(f"checked {checked} Application-based example(s) for bound input polling")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
