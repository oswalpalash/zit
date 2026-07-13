#!/usr/bin/env python3
"""Require Widget lifecycle changes to use their notifying setters.

Direct writes to ``widget.focused``, ``widget.enabled``, and
``widget.visible`` skip dirty-region updates and optional vtable lifecycle
hooks. Direct ``TreeView.Node.expanded`` writes bypass visible-cache updates.
Production widget code and public examples must use the notifying setters.
Unit-test setup remains free to construct state directly.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = (Path("src/widget"), Path("examples"))
SKIP_PATHS = {Path("src/widget/widgets/base_widget.zig")}
TREE_VIEW_PATH = Path("src/widget/widgets/tree_view.zig")
DIRECT_WIDGET_STATE = re.compile(
    r"(?:\b(?:[A-Za-z_][A-Za-z0-9_]*\.)*widget|\]\s*\.\s*\*)\.(?:focused|enabled|visible)\s*=",
)
DIRECT_TREE_EXPANSION = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*\.nodes\.items\[[^\]\n]+\]\.expanded\s*=",
)


def test_body_ranges(source: str) -> list[tuple[int, int]]:
    """Return top-level Zig test declaration ranges, including nested braces."""
    ranges: list[tuple[int, int]] = []
    for match in re.finditer(r'(?m)^test\s+(?:"(?:[^"\\]|\\.)*"|[A-Za-z_][A-Za-z0-9_]*)', source):
        brace = source.find("{", match.end())
        if brace == -1:
            raise RuntimeError(f"test declaration at byte {match.start()} has no body")

        depth = 0
        index = brace
        while index < len(source):
            char = source[index]
            if source.startswith("//", index):
                newline = source.find("\n", index + 2)
                index = len(source) if newline == -1 else newline
                continue
            if char == '"':
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
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    ranges.append((match.start(), index + 1))
                    break
            index += 1
        else:
            raise RuntimeError(f"test declaration at byte {match.start()} has an unterminated body")
    return ranges


def is_test_code(index: int, ranges: list[tuple[int, int]]) -> bool:
    return any(start <= index < end for start, end in ranges)


def line_number(source: str, index: int) -> int:
    return source.count("\n", 0, index) + 1


def iter_files() -> list[Path]:
    files: list[Path] = []
    for directory in SCAN_DIRS:
        root = ROOT / directory
        files.extend(path for path in root.rglob("*.zig") if path.is_file())
    return sorted(files)


def run_self_tests() -> None:
    production = "fn show(subject: anytype) void { subject.widget.visible = false; }\n"
    production_pointer = "fn focus(widgets: anytype, index: usize) void { widgets[index].*.focused = true; }\n"
    test_only = 'test "setup" {\n    subject.widget.visible = false;\n}\n'
    nested_test = 'test "nested" {\n    if (true) { subject.widget.enabled = false; }\n}\n'
    direct_tree_expansion = "fn expand(tree: anytype, index: usize) void { tree.nodes.items[index].expanded = true; }\n"
    tree_test_only = 'test "tree setup" {\n    tree.nodes.items[0].expanded = true;\n}\n'

    if not DIRECT_WIDGET_STATE.search(production):
        raise AssertionError("direct production widget mutation was not detected")
    if not DIRECT_WIDGET_STATE.search(production_pointer):
        raise AssertionError("direct production Widget pointer mutation was not detected")
    if not DIRECT_TREE_EXPANSION.search(direct_tree_expansion):
        raise AssertionError("direct production TreeView expansion was not detected")
    for source in (test_only, nested_test):
        ranges = test_body_ranges(source)
        match = DIRECT_WIDGET_STATE.search(source)
        if match is None or not is_test_code(match.start(), ranges):
            raise AssertionError("test-only widget mutation was not excluded")
    tree_ranges = test_body_ranges(tree_test_only)
    tree_match = DIRECT_TREE_EXPANSION.search(tree_test_only)
    if tree_match is None or not is_test_code(tree_match.start(), tree_ranges):
        raise AssertionError("test-only TreeView expansion was not excluded")


def main() -> int:
    run_self_tests()
    violations: list[str] = []
    files = iter_files()

    for path in files:
        rel = path.relative_to(ROOT)
        if rel in SKIP_PATHS:
            continue
        source = path.read_text(encoding="utf-8")
        ranges = test_body_ranges(source)
        for match in DIRECT_WIDGET_STATE.finditer(source):
            if is_test_code(match.start(), ranges):
                continue
            violations.append(
                f"{rel}:{line_number(source, match.start())}: use Widget.setFocus(), "
                "Widget.setEnabled(), or Widget.setVisible() so lifecycle hooks run"
            )
        if rel != TREE_VIEW_PATH:
            for match in DIRECT_TREE_EXPANSION.finditer(source):
                if is_test_code(match.start(), ranges):
                    continue
                violations.append(
                    f"{rel}:{line_number(source, match.start())}: use TreeView.setExpanded() "
                    "so visible-cache and dirty-state updates run"
                )

    if violations:
        sys.stderr.write("direct Widget lifecycle mutation(s) found:\n")
        for violation in violations:
            sys.stderr.write(f"  - {violation}\n")
        return 1

    print(f"checked Widget lifecycle mutations in {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        sys.stderr.write(f"widget lifecycle mutation check failed: {err}\n")
        raise SystemExit(1)
