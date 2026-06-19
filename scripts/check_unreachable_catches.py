#!/usr/bin/env python3
"""Reject `catch unreachable` in Zig sources.

Zit is a public TUI library, so allocation and I/O failures should either be
propagated, handled best-effort, or explicitly documented. `catch unreachable`
turns recoverable failures into panics and is too easy to copy into production
paths.
"""

from __future__ import annotations

import sys
from pathlib import Path


PATTERN = "catch " + "unreachable"
SCAN_ROOTS = ("src", "examples")
SCAN_FILES = ("build.zig",)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def zig_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for dirname in SCAN_ROOTS:
        files.extend((root / dirname).rglob("*.zig"))
    files.extend(root / name for name in SCAN_FILES)
    return sorted(path for path in files if path.exists())


def main() -> int:
    root = repo_root()
    failures: list[tuple[Path, int, str]] = []

    for path in zig_files(root):
        text = path.read_text(encoding="utf-8")
        for line_no, line in enumerate(text.splitlines(), start=1):
            if PATTERN in line:
                failures.append((path.relative_to(root), line_no, line.strip()))

    if failures:
        sys.stderr.write("recoverable errors must not be converted to `catch unreachable`:\n")
        for path, line_no, line in failures:
            sys.stderr.write(f"  {path}:{line_no}: {line}\n")
        return 1

    print(f"checked {len(zig_files(root))} Zig source file(s) for unreachable catch patterns")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
