#!/usr/bin/env python3
"""Verify mouse-capable public widgets declare hit-test coverage.

The checker parses public widget exports and detects widget structs that handle
mouse events. Each detected widget must be backed by a unit test, smoke test, or
other explicit coverage marker that exercises mouse hit testing. This keeps
rendering and click-coordinate fixes from regressing silently as the widget
catalog grows.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
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


@dataclass(frozen=True)
class CoverageRef:
    path: str
    markers: tuple[str, ...]


MOUSE_HIT_COVERAGE: dict[str, tuple[CoverageRef, ...]] = {
    "Accordion": (CoverageRef("src/widget/widgets/advanced_controls.zig", ("test \"accordion mouse toggles rendered section rows\"", "MouseEvent.init")),),
    "Breadcrumbs": (CoverageRef("src/widget/widgets/advanced_controls.zig", ("test \"breadcrumbs mouse clicks rendered segment only\"", "MouseEvent.init")),),
    "Button": (
        CoverageRef("src/widget/widgets/button.zig", ("test \"button handles decoded terminal mouse coordinates at rendered origin\"", "decodeEventFromBytes")),
        CoverageRef("src/widget/widgets/button.zig", ("test \"button rejects visible border row clicks\"", "MouseEvent.init")),
        CoverageRef("scripts/mouse_alignment_smoke.py", ("send_click(master_fd, 18, 11)", "Button clicked")),
    ),
    "Checkbox": (
        CoverageRef("src/widget/widgets/checkbox.zig", ("test \"checkbox handles decoded terminal mouse coordinates at rendered row\"", "decodeEventFromBytes")),
        CoverageRef("scripts/mouse_alignment_smoke.py", ("send_click(master_fd, 10, 14)", "\"enabled\"")),
    ),
    "ColorPicker": (CoverageRef("src/widget/widgets/color_picker.zig", ("test \"color picker handles mouse and keyboard selection\"", "MouseEvent.init")),),
    "ContextMenu": (CoverageRef("src/widget/widgets/context_menu.zig", ("test \"context menu closes on outside click\"", "MouseEvent.init")),),
    "DropdownMenu": (CoverageRef("src/widget/widgets/dropdown_menu.zig", ("test \"dropdown menu selects item on click\"", "MouseEvent.init")),),
    "FileBrowser": (CoverageRef("src/widget/widgets/file_browser.zig", ("test \"file browser mouse clicks ignore visible border rows\"", "MouseEvent.init")),),
    "InputField": (CoverageRef("src/widget/widgets/input_field.zig", ("test \"input field mouse focus ignores border rows\"", "MouseEvent.init")),),
    "List": (CoverageRef("src/widget/widgets/list.zig", ("test \"list drag reorder updates item order and selection\"", "MouseEvent.init")),),
    "LogView": (CoverageRef("src/widget/widgets/log_view.zig", ("test \"log view mouse wheel scrolls rendered viewport\"", "MouseEvent.init")),),
    "MenuBar": (CoverageRef("src/widget/widgets/menubar.zig", ("test \"menubar mouse selects rendered item row\"", "MouseEvent.init")),),
    "Pagination": (CoverageRef("src/widget/widgets/advanced_controls.zig", ("test \"pagination mouse activates rendered arrows\"", "MouseEvent.init")),),
    "Popup": (CoverageRef("src/widget/widgets/popup.zig", ("test \"popup dismisses on outside mouse press\"", "MouseEvent.init")),),
    "RadioGroup": (CoverageRef("src/widget/widgets/advanced_controls.zig", ("test \"radio group mouse selects rendered option rows\"", "MouseEvent.init")),),
    "RatingStars": (CoverageRef("src/widget/widgets/advanced_controls.zig", ("test \"rating stars mouse maps rendered columns to values\"", "MouseEvent.init")),),
    "ScrollContainer": (CoverageRef("src/widget/widgets/scroll_container.zig", ("test \"scroll container scrolls content with mouse wheel\"", "MouseEvent.init")),),
    "Scrollbar": (CoverageRef("src/widget/widgets/scrollbar.zig", ("test \"scrollbar updates value on scroll event\"", "MouseEvent.init")),),
    "Slider": (CoverageRef("src/widget/widgets/advanced_controls.zig", ("test \"slider mouse maps rendered track to value\"", "MouseEvent.init")),),
    "TabBar": (CoverageRef("src/widget/widgets/tab_view.zig", ("test \"tab bar mouse selects rendered tab row\"", "MouseEvent.init")),),
    "Table": (
        CoverageRef("src/widget/widgets/table.zig", ("test \"bordered table mouse header uses rendered content row\"", "MouseEvent.init")),
        CoverageRef("src/widget/widgets/table.zig", ("test \"bordered table mouse rows skip header separator\"", "MouseEvent.init")),
    ),
    "TextArea": (CoverageRef("src/widget/widgets/text_area.zig", ("test \"text area mouse focus ignores border rows\"", "MouseEvent.init")),),
    "ToggleSwitch": (CoverageRef("src/widget/widgets/advanced_controls.zig", ("test \"toggle switch mouse toggles rendered row only\"", "MouseEvent.init")),),
    "Toolbar": (CoverageRef("src/widget/widgets/advanced_controls.zig", ("test \"toolbar mouse selects rendered item row\"", "MouseEvent.init")),),
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


def handles_mouse(body: str) -> bool:
    markers = (".mouse =>", "event == .mouse", "event != .mouse", "event.mouse")
    return any(marker in body for marker in markers)


def mouse_capable_widgets(exports: dict[str, tuple[str, str]]) -> set[str]:
    capable: set[str] = set()
    for export, (rel_path, source_name) in exports.items():
        path = WIDGET_DIR / rel_path
        text = path.read_text(encoding="utf-8")
        body = struct_body(text, source_name)
        if body is None:
            raise RuntimeError(f"{export}: could not locate struct body for {source_name} in {path.relative_to(ROOT)}")
        if handles_mouse(body):
            capable.add(export)
    return capable


def validate_refs(widget: str, refs: tuple[CoverageRef, ...], errors: list[str]) -> None:
    for ref in refs:
        path = ROOT / ref.path
        if not path.exists():
            errors.append(f"{widget}: coverage file does not exist: {ref.path}")
            continue
        text = path.read_text(encoding="utf-8")
        for marker in ref.markers:
            if marker not in text:
                errors.append(f"{widget}: coverage marker not found in {ref.path}: {marker}")


def main() -> int:
    exports = public_widget_exports()
    mouse_widgets = mouse_capable_widgets(exports)
    declared = set(MOUSE_HIT_COVERAGE)

    errors: list[str] = []
    for widget in sorted(mouse_widgets - declared):
        errors.append(f"{widget}: mouse-capable public widget missing hit-test coverage declaration")
    for widget in sorted(declared - mouse_widgets):
        errors.append(f"{widget}: hit-test coverage declaration has no mouse-capable public widget")
    for widget in sorted(mouse_widgets & declared):
        validate_refs(widget, MOUSE_HIT_COVERAGE[widget], errors)

    if errors:
        print("mouse hit coverage check failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(f"checked {len(mouse_widgets)} mouse-capable public widget hit-test coverage declaration(s)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        print(f"error: {err}", file=sys.stderr)
        raise SystemExit(1)
