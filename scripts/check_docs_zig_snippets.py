#!/usr/bin/env python3
"""Validate public Markdown Zig snippets avoid unstable example patterns."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


PUBLIC_MARKDOWN_ROOTS = (
    Path("README.md"),
    Path("CONTRIBUTING.md"),
    Path("STYLE_GUIDE.md"),
    Path("docs"),
    Path("examples/README.md"),
    Path(".github/PULL_REQUEST_TEMPLATE.md"),
)

FENCE_START = re.compile(r"^```([A-Za-z0-9_-]*)\s*$")
EMPTY_CATCH = re.compile(r"\bcatch\s*\{\s*\}")
UNREACHABLE_CATCH = re.compile(r"\bcatch\s+unreachable\b")
PANIC = re.compile(r"@panic\s*\(")
STANDALONE_UNREACHABLE = re.compile(r"(^|[;{\s])unreachable\s*;")


@dataclass(frozen=True)
class Snippet:
    path: Path
    start_line: int
    text: str


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def markdown_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for rel in PUBLIC_MARKDOWN_ROOTS:
        path = root / rel
        if path.is_dir():
            files.extend(sorted(path.glob("*.md")))
        elif path.exists():
            files.append(path)
    return sorted(set(files))


def zig_snippets(path: Path, root: Path) -> list[Snippet]:
    snippets: list[Snippet] = []
    in_zig = False
    start_line = 0
    lines: list[str] = []

    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        fence = FENCE_START.match(line)
        if fence:
            if in_zig:
                snippets.append(Snippet(path.relative_to(root), start_line, "\n".join(lines)))
                in_zig = False
                lines = []
            else:
                in_zig = fence.group(1).lower() == "zig"
                start_line = number + 1
                lines = []
            continue

        if in_zig:
            lines.append(line)

    return snippets


def snippet_line(snippet: Snippet, index: int) -> int:
    return snippet.start_line + snippet.text.count("\n", 0, index)


def validate_snippet(snippet: Snippet) -> list[str]:
    failures: list[str] = []
    checks = (
        (EMPTY_CATCH, "empty `catch {}` blocks hide recoverable errors in public Zig snippets"),
        (UNREACHABLE_CATCH, "`catch unreachable` turns recoverable errors into panics in public Zig snippets"),
        (PANIC, "`@panic` should not appear in public Zig snippets"),
        (STANDALONE_UNREACHABLE, "`unreachable` should not appear in public Zig snippets"),
    )
    for pattern, message in checks:
        for match in pattern.finditer(snippet.text):
            failures.append(f"{snippet.path}:{snippet_line(snippet, match.start())}: {message}")

    if "std.heap.DebugAllocator" in snippet.text and "std.debug.assert" not in snippet.text:
        failures.append(f"{snippet.path}:{snippet.start_line}: DebugAllocator snippets must assert clean `deinit()`")

    return failures


def main() -> int:
    root = repo_root()
    snippets: list[Snippet] = []
    for path in markdown_files(root):
        snippets.extend(zig_snippets(path, root))

    failures: list[str] = []
    for snippet in snippets:
        failures.extend(validate_snippet(snippet))

    if failures:
        sys.stderr.write("public Markdown Zig snippets must model stable error and allocator handling:\n")
        for failure in failures:
            sys.stderr.write(f"  - {failure}\n")
        return 1

    print(f"checked {len(snippets)} public Markdown Zig snippet(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
