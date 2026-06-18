#!/usr/bin/env python3
"""Verify public widgets have explicit visual or snapshot coverage.

This is intentionally conservative: the checker does not try to prove a widget
is fully tested. It prevents public widget exports from silently existing with
no declared visual/snapshot coverage path.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPORT_FILE = ROOT / "src/widget/widget.zig"
WIDGET_CATALOG = ROOT / "docs/WIDGET_CATALOG.md"

PUBLIC_WIDGET_EXPORT = re.compile(
    r'^pub const (?P<export>[A-Za-z_][A-Za-z0-9_]*) = @import\("widgets/[^"]+"\)\.(?P<source>[A-Za-z_][A-Za-z0-9_]*);',
    re.MULTILINE,
)
CATALOG_PATH_REF = re.compile(r"`((?:src|examples|docs|assets)/[^`]+)`")

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

COVERAGE = {
    "Accordion": ["examples/realworld/widget_gallery_layouts.zig"],
    "AutocompleteInput": ["examples/realworld/widget_gallery_extended.zig"],
    "BatteryIndicator": ["examples/realworld/widget_gallery_extended.zig"],
    "Block": ["examples/realworld/widget_gallery_extended.zig"],
    "Breadcrumbs": ["examples/realworld/widget_gallery.zig"],
    "Button": ["src/testing/testing.zig", "examples/realworld/widget_gallery.zig"],
    "Canvas": ["examples/realworld/widget_gallery_extended.zig"],
    "Chart": ["examples/realworld/widget_gallery_extended.zig"],
    "Checkbox": ["src/testing/testing.zig", "examples/realworld/widget_gallery.zig"],
    "ColorPicker": ["examples/realworld/widget_gallery_extended.zig"],
    "CommandPalette": ["examples/realworld/widget_gallery_extended.zig"],
    "Container": ["examples/realworld/widget_gallery_layouts.zig"],
    "ContextMenu": ["examples/realworld/widget_gallery_layouts.zig"],
    "DateTimePicker": ["examples/realworld/widget_gallery_layouts.zig"],
    "DropdownMenu": ["examples/realworld/widget_gallery_extended.zig"],
    "FileBrowser": ["examples/widget_examples/file_browser_example.zig", "src/widget/widgets/file_browser.zig"],
    "FlexContainer": ["examples/realworld/widget_gallery_layouts.zig"],
    "Gauge": ["examples/realworld/widget_gallery.zig"],
    "GridContainer": ["examples/realworld/widget_gallery_layouts.zig"],
    "ImageWidget": ["examples/realworld/widget_gallery_layouts.zig"],
    "InputField": ["examples/realworld/widget_gallery_extended.zig"],
    "Label": ["src/testing/testing.zig", "examples/realworld/widget_gallery.zig"],
    "List": ["src/testing/testing.zig", "examples/realworld/widget_gallery.zig"],
    "LogView": ["examples/realworld/widget_gallery_extended.zig"],
    "Markdown": ["examples/realworld/widget_gallery_extended.zig"],
    "MenuBar": ["examples/realworld/widget_gallery_extended.zig"],
    "Modal": ["src/testing/testing.zig", "examples/realworld/widget_gallery.zig"],
    "NotificationCenter": ["examples/realworld/widget_gallery_layouts.zig", "examples/realworld/dashboard_demo.zig"],
    "Pagination": ["examples/realworld/widget_gallery.zig"],
    "Paragraph": ["examples/realworld/widget_gallery_extended.zig"],
    "Popup": ["examples/realworld/widget_gallery_extended.zig"],
    "ProgressBar": ["src/testing/testing.zig", "examples/realworld/widget_gallery.zig"],
    "RadioGroup": ["examples/realworld/widget_gallery.zig", "src/widget/widgets/advanced_controls.zig"],
    "RatingStars": ["examples/realworld/widget_gallery.zig"],
    "ResourceMeter": ["examples/realworld/widget_gallery_extended.zig"],
    "RichText": ["examples/realworld/widget_gallery_extended.zig"],
    "ScreenManager": ["examples/realworld/widget_gallery_layouts.zig", "src/widget/widgets/screen_manager.zig"],
    "ScrollContainer": ["examples/realworld/widget_gallery_layouts.zig", "src/widget/widgets/scroll_container.zig"],
    "Scrollbar": ["examples/realworld/widget_gallery_extended.zig"],
    "SignalStrength": ["examples/realworld/widget_gallery_extended.zig"],
    "Slider": ["examples/realworld/widget_gallery.zig"],
    "Sparkline": ["examples/realworld/widget_gallery_extended.zig"],
    "SplitPane": ["examples/realworld/widget_gallery_layouts.zig", "examples/widget_examples/dashboard_example.zig"],
    "StatusBar": ["examples/realworld/widget_gallery.zig"],
    "SyntaxHighlighter": ["examples/realworld/widget_gallery_extended.zig"],
    "TabBar": ["examples/realworld/widget_gallery_layouts.zig"],
    "TabView": ["examples/realworld/widget_gallery_layouts.zig", "src/widget/widgets/tab_view.zig"],
    "Table": ["src/testing/testing.zig", "examples/realworld/widget_gallery.zig"],
    "TextArea": ["examples/realworld/widget_gallery_extended.zig"],
    "ToastManager": ["examples/realworld/widget_gallery_layouts.zig", "examples/widget_examples/notifications_example.zig"],
    "ToggleSwitch": ["examples/realworld/widget_gallery.zig", "src/widget/widgets/advanced_controls.zig"],
    "Toolbar": ["examples/realworld/widget_gallery.zig"],
    "TrafficLight": ["examples/realworld/widget_gallery_extended.zig"],
    "TreeView": ["examples/realworld/widget_gallery_extended.zig"],
    "WizardStepper": ["examples/realworld/widget_gallery_layouts.zig", "examples/realworld/dashboard_demo.zig"],
}


def public_widget_exports() -> dict[str, str]:
    text = EXPORT_FILE.read_text(encoding="utf-8")
    return {match.group("export"): match.group("source") for match in PUBLIC_WIDGET_EXPORT.finditer(text)}


def file_mentions_widget(path: Path, export: str, source: str) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return False
    tokens = (
        f"zit.widget.{export}",
        f"widget.{export}",
        f"{export}.init",
        f"{source}.init",
        f"var {snake_case(export)}",
        f"try {snake_case(export)}",
    )
    return any(token in text for token in tokens)


def snake_case(name: str) -> str:
    out: list[str] = []
    for i, ch in enumerate(name):
        if ch.isupper() and i > 0 and (not name[i - 1].isupper()):
            out.append("_")
        out.append(ch.lower())
    return "".join(out)


def catalog_widget_rows(text: str) -> dict[str, list[str]]:
    rows: dict[str, list[str]] = {}
    for line in text.splitlines():
        if not line.startswith("| ") or line.startswith("| ---"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if not cells or cells[0] == "Widget":
            continue
        rows[cells[0]] = cells
    return rows


def validate_catalog(widgets: dict[str, str], errors: list[str]) -> None:
    try:
        text = WIDGET_CATALOG.read_text(encoding="utf-8")
    except FileNotFoundError:
        errors.append("docs/WIDGET_CATALOG.md: file does not exist")
        return

    rows = catalog_widget_rows(text)
    for name in sorted(widgets):
        if name not in rows:
            errors.append(f"docs/WIDGET_CATALOG.md: missing public widget row: {name}")

    for name in sorted(rows):
        if name not in widgets:
            errors.append(f"docs/WIDGET_CATALOG.md: row has no matching public widget export: {name}")

    for rel in CATALOG_PATH_REF.findall(text):
        if not (ROOT / rel).exists():
            errors.append(f"docs/WIDGET_CATALOG.md: referenced path does not exist: {rel}")


def validate(verbose: bool) -> int:
    exports = public_widget_exports()
    widgets = {name: source for name, source in exports.items() if name not in SUPPORT_EXPORTS}

    errors: list[str] = []
    validate_catalog(widgets, errors)

    for name in sorted(widgets):
        paths = COVERAGE.get(name)
        if not paths:
            errors.append(f"{name}: missing coverage declaration")
            continue
        for rel in paths:
            path = ROOT / rel
            if not path.exists():
                errors.append(f"{name}: coverage file does not exist: {rel}")
                continue
            if not file_mentions_widget(path, name, widgets[name]):
                errors.append(f"{name}: coverage file does not reference widget: {rel}")

    for name in sorted(COVERAGE):
        if name not in widgets:
            errors.append(f"{name}: coverage entry has no matching public widget export")

    if errors:
        print("widget coverage check failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    if verbose:
        print(json.dumps({name: COVERAGE[name] for name in sorted(widgets)}, indent=2))
    print(f"checked {len(widgets)} public widget coverage declaration(s) and catalog row(s)")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verbose", action="store_true", help="print the resolved coverage map")
    args = parser.parse_args()
    return validate(args.verbose)


if __name__ == "__main__":
    raise SystemExit(main())
