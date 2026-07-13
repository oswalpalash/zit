#!/usr/bin/env python3
"""Reject child layout calls from production widget draw callbacks.

Layout publishes geometry, dirty regions, and accessibility bounds. Calling it
from draw makes render cost stateful and can republish bounds every frame.
Widget draw callbacks must consume geometry prepared by their layout callback.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = (ROOT / "src" / "widget", ROOT / "examples")
DRAW_ASSIGNMENT = re.compile(r"\.draw\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*,")
LAYOUT_CALL = re.compile(r"\.\s*layout\s*\(")
TEST_DECLARATION = re.compile(r"(?m)^test\b")


def mask_non_code(source: str) -> str:
    """Replace comments and literals with spaces while preserving offsets."""
    chars = list(source)
    index = 0
    while index < len(source):
        if source.startswith("//", index) or source.startswith("\\\\", index):
            end = source.find("\n", index + 2)
            end = len(source) if end == -1 else end
            for pos in range(index, end):
                chars[pos] = " "
            index = end
            continue
        if source.startswith("/*", index):
            depth = 1
            end = index + 2
            while end < len(source) and depth > 0:
                if source.startswith("/*", end):
                    depth += 1
                    end += 2
                elif source.startswith("*/", end):
                    depth -= 1
                    end += 2
                else:
                    end += 1
            if depth != 0:
                raise RuntimeError("unterminated block comment")
            for pos in range(index, end):
                if chars[pos] != "\n":
                    chars[pos] = " "
            index = end
            continue
        if source[index] in ('"', "'"):
            quote = source[index]
            end = index + 1
            while end < len(source):
                if source[end] == "\\":
                    end += 2
                elif source[end] == quote:
                    end += 1
                    break
                else:
                    end += 1
            else:
                raise RuntimeError("unterminated literal")
            for pos in range(index, min(end, len(source))):
                if chars[pos] != "\n":
                    chars[pos] = " "
            index = end
            continue
        index += 1
    return "".join(chars)


def body_range(masked: str, declaration_end: int) -> tuple[int, int]:
    brace = masked.find("{", declaration_end)
    if brace == -1:
        raise RuntimeError("function or test declaration has no body")
    depth = 0
    for index in range(brace, len(masked)):
        if masked[index] == "{":
            depth += 1
        elif masked[index] == "}":
            depth -= 1
            if depth == 0:
                return brace + 1, index
    raise RuntimeError("function or test declaration has an unterminated body")


def test_ranges(masked: str) -> list[tuple[int, int]]:
    return [(match.start(), body_range(masked, match.end())[1] + 1) for match in TEST_DECLARATION.finditer(masked)]


def in_ranges(index: int, ranges: list[tuple[int, int]]) -> bool:
    return any(start <= index < end for start, end in ranges)


def violations_in(source: str) -> list[tuple[int, str]]:
    masked = mask_non_code(source)
    tests = test_ranges(masked)
    callbacks = {
        match.group(1)
        for match in DRAW_ASSIGNMENT.finditer(masked)
        if not in_ranges(match.start(), tests)
    }
    violations: list[tuple[int, str]] = []
    for callback in sorted(callbacks):
        declaration = re.compile(rf"\bfn\s+{re.escape(callback)}\s*\(")
        for match in declaration.finditer(masked):
            if in_ranges(match.start(), tests):
                continue
            start, end = body_range(masked, match.end())
            call = LAYOUT_CALL.search(masked, start, end)
            if call is not None:
                violations.append((call.start(), callback))
    return violations


def line_number(source: str, index: int) -> int:
    return source.count("\n", 0, index) + 1


def run_self_tests() -> None:
    violation = """
const vtable = VTable{ .draw = renderFrame, };
fn renderFrame(_: *anyopaque) !void { try child.layout(rect); }
"""
    clean = """
const vtable = VTable{ .draw = renderFrame, };
fn renderFrame(_: *anyopaque) !void { child.draw(); }
fn layoutFrame() !void { try child.layout(rect); }
"""
    test_only = """
test "fixture" {
    const vtable = VTable{ .draw = drawFn, };
    fn drawFn(_: *anyopaque) !void { try child.layout(rect); }
}
"""
    literal_only = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void { const message = ".layout("; _ = message; }
"""
    if not violations_in(violation):
        raise AssertionError("draw-time layout was not detected")
    for source in (clean, test_only, literal_only):
        if violations_in(source):
            raise AssertionError("clean or test-only layout was rejected")


def main() -> int:
    run_self_tests()
    violations: list[str] = []
    files = sorted(path for directory in SCAN_DIRS for path in directory.rglob("*.zig") if path.is_file())
    callback_count = 0
    for path in files:
        source = path.read_text(encoding="utf-8")
        masked = mask_non_code(source)
        tests = test_ranges(masked)
        found = violations_in(source)
        callback_count += len(
            {
                match.group(1)
                for match in DRAW_ASSIGNMENT.finditer(masked)
                if not in_ranges(match.start(), tests)
            }
        )
        for index, callback in found:
            rel = path.relative_to(ROOT)
            violations.append(
                f"{rel}:{line_number(source, index)}: {callback} must consume geometry prepared by layout; "
                "do not call Widget.layout() from draw"
            )

    if violations:
        sys.stderr.write("draw/layout boundary violation(s) found:\n")
        for violation in violations:
            sys.stderr.write(f"  - {violation}\n")
        return 1

    print(f"checked draw/layout boundaries for {callback_count} callback name(s) in {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, RuntimeError) as err:
        sys.stderr.write(f"draw/layout boundary check failed: {err}\n")
        raise SystemExit(1)
