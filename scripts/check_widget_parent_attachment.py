#!/usr/bin/env python3
"""Require production widget parent links to be created through Widget.attachTo.

Direct positive writes to ``Widget.parent`` bypass the single-parent ownership
check and can silently leave two owners referencing the same widget. Detach
cleanup may still assign ``null``, and unit tests may construct invalid state
directly when exercising rejection paths.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from check_widget_lifecycle_mutation import is_test_code, line_number, test_body_ranges


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = (Path("src/widget/widgets"), Path("examples"))
BASE_WIDGET = Path("src/widget/widgets/base_widget.zig")
DIRECT_PARENT_ASSIGNMENT = re.compile(
    r"(?P<target>\b[A-Za-z_][A-Za-z0-9_]*(?:(?:\.[A-Za-z_][A-Za-z0-9_]*)|(?:\[[^\]\n]+\])|(?:\.\*))*)"
    r"\.parent\s*=(?!=)\s*(?P<value>[^;\n]+);",
)


def declaration_body_range(source: str, declaration: str) -> tuple[int, int]:
    match = re.search(rf"(?m)^\s*pub fn {re.escape(declaration)}\b", source)
    if match is None:
        raise RuntimeError(f"missing declaration: {declaration}")
    brace = source.find("{", match.end())
    if brace == -1:
        raise RuntimeError(f"declaration {declaration} has no body")

    depth = 0
    index = brace
    while index < len(source):
        if source.startswith("//", index):
            newline = source.find("\n", index + 2)
            index = len(source) if newline == -1 else newline
            continue
        if source[index] == '"':
            index += 1
            while index < len(source):
                if source[index] == "\\":
                    index += 2
                elif source[index] == '"':
                    index += 1
                    break
                else:
                    index += 1
            continue
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return match.start(), index + 1
        index += 1
    raise RuntimeError(f"declaration {declaration} has an unterminated body")


def is_line_comment(source: str, index: int) -> bool:
    line_start = source.rfind("\n", 0, index) + 1
    comment = source.find("//", line_start, index)
    return comment != -1


def iter_files() -> list[Path]:
    files: list[Path] = []
    for directory in SCAN_DIRS:
        root = ROOT / directory
        files.extend(path for path in root.rglob("*.zig") if path.is_file())
    return sorted(files)


def run_self_tests() -> None:
    production = "fn attach(child: *Widget, owner: *Widget) void { child.parent = owner; }\n"
    indexed = "fn attach(items: anytype, i: usize, owner: *Widget) void { items[i].*.parent = owner; }\n"
    detach = "fn detach(child: *Widget) void { child.parent = null; }\n"
    test_only = 'test "invalid state" {\n    child.parent = owner;\n}\n'
    initializer = "const node = Node{ .parent = parent_index };\n"

    for source in (production, indexed):
        match = DIRECT_PARENT_ASSIGNMENT.search(source)
        if match is None or match.group("value").strip() == "null":
            raise AssertionError("direct positive parent assignment was not detected")
    match = DIRECT_PARENT_ASSIGNMENT.search(detach)
    if match is None or match.group("value").strip() != "null":
        raise AssertionError("parent detach was not recognized")
    test_match = DIRECT_PARENT_ASSIGNMENT.search(test_only)
    if test_match is None or not is_test_code(test_match.start(), test_body_ranges(test_only)):
        raise AssertionError("test-only parent mutation was not excluded")
    if DIRECT_PARENT_ASSIGNMENT.search(initializer) is not None:
        raise AssertionError("parent struct initializer was misclassified as a Widget mutation")


def main() -> int:
    run_self_tests()
    violations: list[str] = []
    files = iter_files()
    shared_attachment_count = 0

    for path in files:
        rel = path.relative_to(ROOT)
        source = path.read_text(encoding="utf-8")
        ranges = test_body_ranges(source)
        attach_range = declaration_body_range(source, "attachTo") if rel == BASE_WIDGET else None

        for match in DIRECT_PARENT_ASSIGNMENT.finditer(source):
            if is_line_comment(source, match.start()) or is_test_code(match.start(), ranges):
                continue
            if match.group("value").strip() == "null":
                continue
            if (
                rel == BASE_WIDGET
                and attach_range is not None
                and attach_range[0] <= match.start() < attach_range[1]
                and match.group("target") == "self"
                and match.group("value").strip() == "parent"
            ):
                shared_attachment_count += 1
                continue
            violations.append(
                f"{rel}:{line_number(source, match.start())}: use Widget.attachTo() "
                "so cross-parent ownership is rejected"
            )

    if shared_attachment_count != 1:
        violations.append(
            f"{BASE_WIDGET}: expected exactly one shared parent assignment in Widget.attachTo(), "
            f"found {shared_attachment_count}"
        )

    if violations:
        sys.stderr.write("direct Widget parent attachment(s) found:\n")
        for violation in violations:
            sys.stderr.write(f"  - {violation}\n")
        return 1

    print(f"checked Widget parent attachments in {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        sys.stderr.write(f"widget parent attachment check failed: {err}\n")
        raise SystemExit(1)
