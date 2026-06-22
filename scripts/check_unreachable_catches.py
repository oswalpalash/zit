#!/usr/bin/env python3
"""Reject risky catch patterns in Zig sources.

Zit is a public TUI library, so allocation and I/O failures should either be
propagated, handled best-effort, or explicitly documented. `catch unreachable`
turns recoverable failures into panics and is too easy to copy into production
paths. Silent `catch {}` on capacity reservation is equally risky because it
lets later rendering/input paths continue after memory pressure invalidated a
precondition they were trying to establish.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


PATTERN = "catch " + "unreachable"
SILENT_CAPACITY_CATCH = re.compile(
    r"\.(?:ensureTotalCapacity|ensureUnusedCapacity)\s*\([^;]*?\)\s*catch\s*\{\s*\}",
    re.DOTALL,
)
EMPTY_CATCH = re.compile(r"catch\s*\{\s*\}")
SCAN_ROOTS = ("src", "examples")
SCAN_FILES = ("build.zig",)
CRITICAL_EMPTY_CATCH_FILES = {
    Path("src/event/event.zig"),
    Path("src/render/render.zig"),
    Path("src/terminal/terminal.zig"),
    Path("src/widget/accessibility.zig"),
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def zig_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for dirname in SCAN_ROOTS:
        files.extend((root / dirname).rglob("*.zig"))
    files.extend(root / name for name in SCAN_FILES)
    return sorted(path for path in files if path.exists())


def source_line_no(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def run_self_tests() -> None:
    unsafe = "list.ensureTotalCapacity(allocator, 64) catch {};"
    safe = "try list.ensureTotalCapacity(allocator, 64);"
    empty_catch = "optionalFeature() catch {};"
    multiline_unsafe = """
list.ensureUnusedCapacity(
    allocator,
    1,
) catch {};
"""
    if SILENT_CAPACITY_CATCH.search(unsafe) is None:
        raise AssertionError("silent capacity catch fixture was not detected")
    if SILENT_CAPACITY_CATCH.search(multiline_unsafe) is None:
        raise AssertionError("multiline silent capacity catch fixture was not detected")
    if SILENT_CAPACITY_CATCH.search(safe) is not None:
        raise AssertionError("propagated capacity error fixture was incorrectly rejected")
    if EMPTY_CATCH.search(empty_catch) is None:
        raise AssertionError("empty catch fixture was not detected")


def main() -> int:
    run_self_tests()
    root = repo_root()
    failures: list[tuple[Path, int, str]] = []
    silent_capacity_failures: list[tuple[Path, int, str]] = []
    critical_empty_catches: list[tuple[Path, int, str]] = []

    for path in zig_files(root):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(root)
        for current_line_no, line in enumerate(text.splitlines(), start=1):
            if PATTERN in line:
                failures.append((rel, current_line_no, line.strip()))
        for match in SILENT_CAPACITY_CATCH.finditer(text):
            snippet = " ".join(match.group(0).split())
            silent_capacity_failures.append((rel, source_line_no(text, match.start()), snippet))
        if rel in CRITICAL_EMPTY_CATCH_FILES:
            for match in EMPTY_CATCH.finditer(text):
                snippet = " ".join(match.group(0).split())
                critical_empty_catches.append((rel, source_line_no(text, match.start()), snippet))

    if failures:
        sys.stderr.write("recoverable errors must not be converted to `catch unreachable`:\n")
        for path, line_no, line in failures:
            sys.stderr.write(f"  {path}:{line_no}: {line}\n")
        return 1

    if silent_capacity_failures:
        sys.stderr.write("capacity reservation failures must be propagated or handled explicitly:\n")
        for path, line_no, line in silent_capacity_failures:
            sys.stderr.write(f"  {path}:{line_no}: {line}\n")
        return 1

    if critical_empty_catches:
        sys.stderr.write("critical source modules must not silently swallow errors with `catch {}`:\n")
        for path, line_no, line in critical_empty_catches:
            sys.stderr.write(f"  {path}:{line_no}: {line}\n")
        return 1

    print(f"checked {len(zig_files(root))} Zig source file(s) for risky catch patterns")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
