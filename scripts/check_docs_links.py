#!/usr/bin/env python3
"""Validate public Markdown documentation links and index coverage."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse


MARKDOWN_LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
PUBLIC_MARKDOWN_ROOTS = (
    Path("README.md"),
    Path("CONTRIBUTING.md"),
    Path("STYLE_GUIDE.md"),
    Path("docs"),
    Path("examples/README.md"),
    Path(".github/PULL_REQUEST_TEMPLATE.md"),
)
HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
HTML_TAG = re.compile(r"<[^>]+>")


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


def is_external(target: str) -> bool:
    parsed = urlparse(target)
    return parsed.scheme in {"http", "https", "mailto"}


def split_link_target(raw: str) -> tuple[str, str]:
    target = raw.strip()
    if not target or target.startswith("#") or is_external(target):
        if target.startswith("#"):
            return "", target[1:]
        return "", ""
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    path, _, fragment = target.partition("#")
    return path, fragment


def slugify_heading(text: str) -> str:
    text = HTML_TAG.sub("", text)
    text = text.replace("`", "")
    text = text.strip().lower()
    kept: list[str] = []
    for ch in text:
        if ch.isalnum() or ch in {" ", "-", "_"}:
            kept.append(ch)
    return re.sub(r"\s+", "-", "".join(kept).strip())


def markdown_anchors(path: Path) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = HEADING.match(line)
        if not match:
            continue
        base = slugify_heading(match.group(2))
        if not base:
            continue
        count = counts.get(base, 0)
        counts[base] = count + 1
        anchors.add(base if count == 0 else f"{base}-{count}")
    return anchors


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def validate_links(root: Path, files: list[Path]) -> list[str]:
    errors: list[str] = []
    anchor_cache: dict[Path, set[str]] = {}
    for path in files:
        text = path.read_text(encoding="utf-8")
        for match in MARKDOWN_LINK.finditer(text):
            target_path, fragment = split_link_target(match.group(1))
            if not target_path and not fragment:
                continue
            line = line_number(text, match.start())
            decoded = unquote(target_path)
            if not decoded:
                resolved = path
            else:
                resolved = (path.parent / decoded).resolve()
                try:
                    resolved.relative_to(root)
                except ValueError:
                    errors.append(f"{path.relative_to(root)}:{line}: link escapes repo root: {match.group(1)}")
                    continue
                if not resolved.exists():
                    errors.append(f"{path.relative_to(root)}:{line}: broken link target: {match.group(1)}")
                    continue
            if not fragment:
                continue
            if resolved.suffix.lower() != ".md":
                continue
            anchor = unquote(fragment).lower()
            if resolved not in anchor_cache:
                anchor_cache[resolved] = markdown_anchors(resolved)
            if anchor not in anchor_cache[resolved]:
                errors.append(f"{path.relative_to(root)}:{line}: broken Markdown anchor `{fragment}` in link target: {match.group(1)}")
    return errors


def validate_docs_index(root: Path) -> list[str]:
    index = root / "docs" / "README.md"
    if not index.exists():
        return ["docs/README.md is missing"]

    text = index.read_text(encoding="utf-8")
    errors: list[str] = []
    for path in sorted((root / "docs").glob("*.md")):
        if path.name == "README.md":
            continue
        if f"]({path.name})" not in text:
            errors.append(f"docs/README.md must link docs/{path.name}")
    return errors


def main() -> int:
    root = repo_root()
    files = markdown_files(root)
    errors = validate_links(root, files)
    errors.extend(validate_docs_index(root))

    if errors:
        sys.stderr.write("docs link check failed:\n")
        for error in errors:
            sys.stderr.write(f"  - {error}\n")
        return 1

    print(f"checked {len(files)} public Markdown file(s) for relative links, anchors, and docs index coverage")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
