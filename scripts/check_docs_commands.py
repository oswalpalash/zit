#!/usr/bin/env python3
"""Validate command references in public Markdown docs."""

from __future__ import annotations

import re
import shlex
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

CODE_SPAN = re.compile(r"`([^`\n]+)`")
FENCE_START = re.compile(r"^```([A-Za-z0-9_-]*)\s*$")
BUILD_STEP = re.compile(r'\bb\.step\("([^"]+)"')
DECLARED_STEP_NAME = re.compile(r'\.step_name = "([^"]+)"')
SHELL_FENCES = {"", "sh", "shell", "bash", "zsh", "console"}


@dataclass(frozen=True)
class CommandRef:
    path: Path
    line: int
    command: str


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


def build_steps(root: Path) -> set[str]:
    text = (root / "build.zig").read_text(encoding="utf-8")
    steps = set(BUILD_STEP.findall(text))
    steps.update(DECLARED_STEP_NAME.findall(text))
    steps.add("install")
    return steps


def looks_like_checked_command(text: str) -> bool:
    stripped = text.strip()
    return (
        stripped.startswith("python3 scripts/")
        or stripped.startswith("zig build ")
        or stripped == "zig build"
        or stripped.startswith("zig fmt ")
    )


def normalize_shell_line(line: str) -> str:
    stripped = line.strip()
    if stripped.startswith("$ "):
        stripped = stripped[2:].strip()
    return stripped


def command_refs(path: Path, root: Path) -> list[CommandRef]:
    refs: list[CommandRef] = []
    text = path.read_text(encoding="utf-8")

    for match in CODE_SPAN.finditer(text):
        command = match.group(1).strip()
        if looks_like_checked_command(command):
            refs.append(CommandRef(path.relative_to(root), text.count("\n", 0, match.start()) + 1, command))

    in_fence = False
    shell_fence = False
    for number, line in enumerate(text.splitlines(), start=1):
        fence = FENCE_START.match(line)
        if fence:
            lang = fence.group(1).lower()
            if in_fence:
                in_fence = False
                shell_fence = False
            else:
                in_fence = True
                shell_fence = lang in SHELL_FENCES
            continue

        if not shell_fence:
            continue

        command = normalize_shell_line(line)
        if looks_like_checked_command(command):
            refs.append(CommandRef(path.relative_to(root), number, command))

    return refs


def command_tokens(command: str) -> list[str] | None:
    try:
        return shlex.split(command)
    except ValueError:
        return None


def validate_python_script(root: Path, ref: CommandRef, tokens: list[str]) -> list[str]:
    if len(tokens) < 2:
        return [f"{ref.path}:{ref.line}: incomplete python command: {ref.command}"]

    script = tokens[1]
    if not script.startswith("scripts/"):
        return []

    script_path = root / script
    if not script_path.is_file():
        return [f"{ref.path}:{ref.line}: referenced script does not exist: {script}"]
    if script_path.suffix != ".py":
        return [f"{ref.path}:{ref.line}: referenced script is not a Python file: {script}"]
    return []


def validate_zig_build(ref: CommandRef, tokens: list[str], steps: set[str]) -> list[str]:
    if len(tokens) < 2 or tokens[:2] != ["zig", "build"]:
        return []
    if len(tokens) == 2:
        return []

    step = tokens[2]
    if step.startswith("-"):
        return []
    if step not in steps:
        return [f"{ref.path}:{ref.line}: referenced zig build step is not declared in build.zig: {step}"]
    return []


def validate_zig_fmt(root: Path, ref: CommandRef, tokens: list[str]) -> list[str]:
    if len(tokens) < 2 or tokens[:2] != ["zig", "fmt"]:
        return []

    errors: list[str] = []
    for token in tokens[2:]:
        if token.startswith("-"):
            continue
        target = root / token.rstrip("/")
        if not target.exists():
            errors.append(f"{ref.path}:{ref.line}: referenced zig fmt path does not exist: {token}")
    return errors


def validate_ref(root: Path, ref: CommandRef, steps: set[str]) -> list[str]:
    tokens = command_tokens(ref.command)
    if tokens is None:
        return [f"{ref.path}:{ref.line}: command is not shell-parseable: {ref.command}"]
    if not tokens:
        return []

    if tokens[0] == "python3":
        return validate_python_script(root, ref, tokens)
    if tokens[:2] == ["zig", "build"]:
        return validate_zig_build(ref, tokens, steps)
    if tokens[:2] == ["zig", "fmt"]:
        return validate_zig_fmt(root, ref, tokens)
    return []


def main() -> int:
    root = repo_root()
    steps = build_steps(root)
    refs: list[CommandRef] = []
    for path in markdown_files(root):
        refs.extend(command_refs(path, root))

    errors: list[str] = []
    for ref in refs:
        errors.extend(validate_ref(root, ref, steps))

    if errors:
        sys.stderr.write("docs command check failed:\n")
        for error in errors:
            sys.stderr.write(f"  - {error}\n")
        return 1

    print(f"checked {len(refs)} public Markdown command reference(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
