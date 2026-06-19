#!/usr/bin/env python3
"""Require public examples to restore terminal state they enable."""

from __future__ import annotations

import sys
from pathlib import Path
import re


PAIRS = (
    ("enterAlternateScreen", "exitAlternateScreen"),
    ("enableRawMode", "disableRawMode"),
    ("enableMouse", "disableMouse"),
    ("hideCursor", "showCursor"),
)

SILENT_CLEANUP_PATTERNS = (
    re.compile(r"\b(?:term|terminal)\.deinit\(\)\s+catch\s+\{\s*\}"),
    re.compile(r"\.(?:exitAlternateScreen|disableRawMode|showCursor)\(\)\s+catch\s+\{\s*\}"),
    re.compile(r"\binput_handler\.disableMouse\(\)\s+catch\s+\{\s*\}"),
)

PUBLIC_SNIPPET_PATHS = (
    Path("README.md"),
    Path("docs/API.md"),
    Path("docs/APP_LOOP_TUTORIAL.md"),
    Path("src/terminal/terminal.zig"),
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def iter_example_sources(root: Path) -> list[Path]:
    return sorted((root / "examples").rglob("*.zig"))


def iter_silent_cleanup_sources(root: Path) -> list[Path]:
    paths = [path for path in iter_example_sources(root) if "benchmarks" not in path.parts]
    paths.extend(root / rel for rel in PUBLIC_SNIPPET_PATHS)
    return sorted(set(paths))


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def validate_no_silent_cleanup(root: Path) -> list[str]:
    failures: list[str] = []
    for path in iter_silent_cleanup_sources(root):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(root)
        for pattern in SILENT_CLEANUP_PATTERNS:
            for match in pattern.finditer(text):
                failures.append(f"{rel}:{line_number(text, match.start())}: terminal cleanup errors must be reported, not swallowed with `catch {{}}`")
    return failures


def main() -> int:
    root = repo_root()
    failures: list[str] = []
    checked = 0

    for path in iter_example_sources(root):
        if "benchmarks" in path.parts:
            continue

        text = path.read_text(encoding="utf-8")
        if "initInteractive(" not in text:
            continue

        checked += 1
        rel = path.relative_to(root)
        for setup, cleanup in PAIRS:
            setup_call = f".{setup}("
            cleanup_call = f".{cleanup}("
            setup_index = text.find(setup_call)
            cleanup_index = text.find(cleanup_call)
            setup_present = setup_index >= 0
            cleanup_present = cleanup_index >= 0
            if setup_present and not cleanup_present:
                failures.append(f"{rel}: calls {setup} without {cleanup}")
            if cleanup_present and not setup_present:
                failures.append(f"{rel}: calls {cleanup} without {setup}")
            if setup_present and cleanup_present:
                if cleanup_index < setup_index:
                    failures.append(f"{rel}: calls {cleanup} before {setup}")
                elif "defer" not in text[setup_index:cleanup_index]:
                    failures.append(f"{rel}: restores {cleanup} without deferring it after {setup}")

    failures.extend(validate_no_silent_cleanup(root))

    if failures:
        sys.stderr.write("interactive examples must restore terminal state they enable and report cleanup failures:\n")
        for failure in failures:
            sys.stderr.write(f"  - {failure}\n")
        return 1

    print(f"checked {checked} interactive example(s) for terminal-state cleanup symmetry and silent cleanup catches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
