#!/usr/bin/env python3
"""Reject unsafe concrete owner casts from embedded Widget vtable pointers."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = ("src", "examples", "docs")

RAW_WIDGET_OWNER_CAST = re.compile(
    r"@as\(\s*\*(?:const\s+)?(?P<type>[A-Za-z_][A-Za-z0-9_.]*)\s*,\s*"
    r"@ptrCast\(\s*@alignCast\(\s*widget_ptr\s*\)\s*\)\s*\)"
)
ALLOWED_WIDGET_POINTER_TYPES = {
    "Widget",
    "base.Widget",
    "widget.Widget",
}


def iter_files() -> list[Path]:
    files: list[Path] = []
    for dirname in SCAN_DIRS:
        root = ROOT / dirname
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix in {".zig", ".md"} and path.is_file():
                files.append(path)
    return sorted(files)


def main() -> int:
    files = iter_files()
    violations: list[str] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for match in RAW_WIDGET_OWNER_CAST.finditer(line):
                target_type = match.group("type")
                if target_type in ALLOWED_WIDGET_POINTER_TYPES:
                    continue
                rel = path.relative_to(ROOT)
                violations.append(f'{rel}:{line_no}: use @fieldParentPtr("widget", widget_ref) instead of raw-casting widget_ptr to *{target_type}')

    if violations:
        sys.stderr.write("unsafe widget owner cast(s) found:\n")
        for item in violations:
            sys.stderr.write(f"  - {item}\n")
        return 1

    print(f"checked widget owner casts in {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
