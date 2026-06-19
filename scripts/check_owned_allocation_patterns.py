#!/usr/bin/env python3
"""Reject owned-allocation patterns that are not transactional.

Public widgets commonly take ownership of duplicated strings. Two patterns are
especially error-prone:

- appending ``try allocator.dupe(...)`` directly into a collection, which leaks
  the duplicate if the append allocation fails;
- freeing an owned field before assigning a replacement from a fallible
  duplicate allocation, which loses the old value on ``OutOfMemory``.

Use reserve-before-duplicate/append helpers, ``errdefer`` cleanup, or
duplicate-before-free replacement instead.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = ("src", "examples", "docs", "README.md")

APPEND_DUPLICATE = re.compile(
    r"\.(?:append|insert)\s*\([^;\n]*try\s+(?:self\.)?allocator\.dupe\s*\(",
)
FREE_BEFORE_DUPLICATE = re.compile(
    r"(?:self\.)?allocator\.free\(\s*self\.(?P<free_field>[A-Za-z_][A-Za-z0-9_]*)\s*\)\s*;\s*"
    r"self\.(?P<assign_field>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*try\s+(?:self\.)?allocator\.dupe\s*\(",
    re.DOTALL,
)


def iter_files() -> list[Path]:
    files: list[Path] = []
    for root_name in SCAN_ROOTS:
        root = ROOT / root_name
        if root.is_file():
            files.append(root)
            continue
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix in {".zig", ".md"} and path.is_file():
                files.append(path)
    return sorted(files)


def line_no(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def main() -> int:
    violations: list[str] = []
    files = iter_files()
    for path in files:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)

        for match in APPEND_DUPLICATE.finditer(text):
            violations.append(
                f"{rel}:{line_no(text, match.start())}: reserve collection capacity before duplicating owned data, "
                "or use an errdefer-cleaned temporary before append/insert"
            )

        for match in FREE_BEFORE_DUPLICATE.finditer(text):
            if match.group("free_field") != match.group("assign_field"):
                continue
            field = match.group("free_field")
            violations.append(
                f"{rel}:{line_no(text, match.start())}: duplicate replacement for `self.{field}` before freeing "
                "the existing value"
            )

    if violations:
        sys.stderr.write("non-transactional owned allocation pattern(s) found:\n")
        for violation in violations:
            sys.stderr.write(f"  - {violation}\n")
        return 1

    print(f"checked owned allocation patterns in {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
