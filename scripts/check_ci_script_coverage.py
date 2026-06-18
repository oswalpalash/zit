#!/usr/bin/env python3
"""Ensure CI compiles every Python script used by release verification."""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def release_script_targets(root: Path) -> set[str]:
    source = root / "scripts" / "release_verify.py"
    tree = ast.parse(source.read_text(encoding="utf-8"), filename=str(source))
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "SCRIPT_COMPILE_TARGETS":
                    value = ast.literal_eval(node.value)
                    return {str(item) for item in value}
    raise RuntimeError("could not find SCRIPT_COMPILE_TARGETS in scripts/release_verify.py")


def ci_py_compile_targets(root: Path) -> set[str]:
    workflow = root / ".github" / "workflows" / "build.yaml"
    text = workflow.read_text(encoding="utf-8")
    targets: set[str] = set()
    for line in text.splitlines():
        if "python3 -m py_compile" not in line:
            continue
        targets.update(re.findall(r"scripts/[A-Za-z0-9_./-]+\.py", line))
    if not targets:
        raise RuntimeError("could not find a python3 -m py_compile line in .github/workflows/build.yaml")
    return targets


def main() -> int:
    root = repo_root()
    expected = release_script_targets(root)
    actual = ci_py_compile_targets(root)

    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing or extra:
        if missing:
            sys.stderr.write("CI py_compile missing release script(s): " + ", ".join(missing) + "\n")
        if extra:
            sys.stderr.write("CI py_compile has script(s) absent from release verification: " + ", ".join(extra) + "\n")
        return 1

    print(f"checked CI py_compile coverage for {len(expected)} release script(s)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        sys.stderr.write(f"error: {err}\n")
        raise SystemExit(1)
