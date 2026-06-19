#!/usr/bin/env python3
"""Verify terminal mouse coordinates are normalized at one boundary.

The terminal reports mouse positions with one-based columns and rows. Zit
widgets and renderer/layout rects use zero-based screen coordinates. To keep
clicks aligned with rendered cells, protocol decoders must route raw terminal
coordinates through ``MouseEvent.fromTerminalCoordinates`` exactly at the input
boundary instead of open-coding normalization in parser bodies.
"""

from __future__ import annotations

import sys
from pathlib import Path


MOUSE_DECODER_NAMES = ("parseMouseEventLegacy", "parseMouseEventSgr")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def function_body(source: str, name: str) -> str:
    marker = f"fn {name}("
    start = source.find(marker)
    if start == -1:
        raise RuntimeError(f"missing function: {name}")

    brace = source.find("{", start)
    if brace == -1:
        raise RuntimeError(f"{name}: missing function body")

    depth = 0
    for index in range(brace, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : index]

    raise RuntimeError(f"{name}: unterminated function body")


def validate_input_contract(source: str) -> list[str]:
    errors: list[str] = []

    if "pub fn fromTerminalCoordinates(" not in source:
        errors.append("MouseEvent is missing fromTerminalCoordinates constructor")
    if "terminalMouseCoordToScreenCoord(terminal_x)" not in source or "terminalMouseCoordToScreenCoord(terminal_y)" not in source:
        errors.append("MouseEvent.fromTerminalCoordinates must normalize both terminal_x and terminal_y")

    for name in MOUSE_DECODER_NAMES:
        try:
            body = function_body(source, name)
        except RuntimeError as err:
            errors.append(str(err))
            continue

        if "MouseEvent.fromTerminalCoordinates(" not in body:
            errors.append(f"{name}: must construct decoded events through MouseEvent.fromTerminalCoordinates")
        if "MouseEvent{" in body:
            errors.append(f"{name}: must not directly construct MouseEvent with parser-local coordinates")
        if "terminalMouseCoordToScreenCoord(" in body:
            errors.append(f"{name}: must not open-code coordinate normalization; use MouseEvent.fromTerminalCoordinates")

    return errors


def main() -> int:
    root = repo_root()
    input_source = root / "src" / "input" / "input.zig"
    errors = validate_input_contract(input_source.read_text(encoding="utf-8"))
    if errors:
        sys.stderr.write("mouse coordinate contract check failed:\n")
        for error in errors:
            sys.stderr.write(f"  - {error}\n")
        return 1

    print(f"checked {len(MOUSE_DECODER_NAMES)} terminal mouse decoder coordinate contract(s)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        sys.stderr.write(f"error: {err}\n")
        raise SystemExit(1)
