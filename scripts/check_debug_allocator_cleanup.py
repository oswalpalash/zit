#!/usr/bin/env python3
"""Require DebugAllocator users to assert clean deinit.

DebugAllocator reports leaks and invalid frees, but examples commonly run as
standalone programs where stderr can be missed. Public examples and memory tests
must make those diagnostics fatal by checking ``deinit() == .ok``. Public docs
are checked too, so copy-paste snippets teach the same allocator contract.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


CHECK_ROOTS = (
    Path("examples"),
    Path("src/memory/tests"),
    Path("src/quickstart.zig"),
    Path("README.md"),
    Path("docs"),
)

FORBIDDEN_PATTERNS = (
    re.compile(r"defer\s+_\s*=\s*[A-Za-z_][A-Za-z0-9_]*\.deinit\(\);"),
    re.compile(r"(?<!defer\s)_\s*=\s*[A-Za-z_][A-Za-z0-9_]*\.deinit\(\);"),
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def iter_checked_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for check_root in CHECK_ROOTS:
        path = root / check_root
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("*.zig")))
            files.extend(sorted(path.rglob("*.md")))
    return sorted(files)


def main() -> int:
    root = repo_root()
    failures: list[str] = []
    checked = 0

    for path in iter_checked_files(root):
        text = path.read_text(encoding="utf-8")
        if "std.heap.DebugAllocator" not in text:
            continue
        checked += 1
        rel = path.relative_to(root)
        for pattern in FORBIDDEN_PATTERNS:
            for match in pattern.finditer(text):
                failures.append(f"{rel}: ignores DebugAllocator deinit with `{match.group(0)}`")
        if "deinit() == .ok" not in text:
            failures.append(f"{rel}: DebugAllocator cleanup does not assert `.ok`")

    if failures:
        for failure in failures:
            sys.stderr.write(failure + "\n")
        return 1

    print(f"checked DebugAllocator cleanup in {checked} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
