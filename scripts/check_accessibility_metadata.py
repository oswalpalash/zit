#!/usr/bin/env python3
"""Verify public widgets define accessibility metadata.

Zit publicly claims accessibility roles and focus announcements as built-in
behavior. Every exported public widget should therefore call setAccessibility in
its owner struct so Application accessibility registration has stable semantic
metadata to work with.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_FILE = ROOT / "src/widget/widget.zig"
WIDGET_DIR = ROOT / "src/widget"

PUBLIC_WIDGET_EXPORT = re.compile(
    r'^pub const (?P<export>[A-Za-z_][A-Za-z0-9_]*) = @import\("(?P<path>widgets/[^"]+)"\)\.(?P<source>[A-Za-z_][A-Za-z0-9_]*);',
    re.MULTILINE,
)

SUPPORT_EXPORTS = {
    "BaseWidget",
    "BorderStyle",
    "ChartType",
    "ContextMenuItem",
    "FocusDirection",
    "GaugeOrientation",
    "ImageRenderMode",
    "LogLevel",
    "ProgressDirection",
    "Screen",
    "ScreenLifecycle",
    "ScreenTransitions",
    "ScrollOrientation",
    "SplitOrientation",
    "TabItem",
    "TabLoader",
    "TabSpec",
    "ToastLevel",
    "Widget",
}


def public_widget_exports() -> dict[str, tuple[str, str]]:
    text = EXPORT_FILE.read_text(encoding="utf-8")
    return {
        match.group("export"): (match.group("path"), match.group("source"))
        for match in PUBLIC_WIDGET_EXPORT.finditer(text)
        if match.group("export") not in SUPPORT_EXPORTS
    }


def struct_body(source: str, name: str) -> str | None:
    marker = f"pub const {name} = struct"
    start = source.find(marker)
    if start == -1:
        return None

    brace = source.find("{", start)
    if brace == -1:
        return None

    depth = 0
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : index]
    return None


def main() -> int:
    errors: list[str] = []
    for export, (rel_path, source_name) in sorted(public_widget_exports().items()):
        path = WIDGET_DIR / rel_path
        text = path.read_text(encoding="utf-8")
        body = struct_body(text, source_name)
        if body is None:
            errors.append(f"{export}: could not locate struct body for {source_name} in {path.relative_to(ROOT)}")
            continue
        if "setAccessibility" not in body:
            errors.append(f"{export}: public widget does not set accessibility metadata")

    if errors:
        print("accessibility metadata check failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("checked accessibility metadata for all public widget exports")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
