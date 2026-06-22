#!/usr/bin/env python3
"""Reject stale I/O event ownership examples.

`IoEventManager.watchFile` and `connectToServer` return manager-owned contexts.
Calling `deinit()` directly on those returned pointers leaves stale pointers in
the manager and can double-free during manager teardown. Public docs and examples
must route cleanup back through the manager/application facade.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = ("src", "examples", "docs", "README.md")
MANAGER_OWNED_ASSIGNMENT = re.compile(
    r"\b(?:const|var)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*try\s+[^;\n]*\."
    r"(?P<factory>watchFile|connectToServer)\s*\(",
)
DIRECT_DEINIT = re.compile(r"\b(?:defer\s+)?(?P<name>[A-Za-z_][A-Za-z0-9_]*)\.deinit\s*\(")
IDEMPOTENT_IO_CONTEXT_DEINIT = re.compile(
    r"///\s+Safety:\s+Idempotent;[^\n]*\n\s*pub\s+fn\s+deinit\s*\("
)


def iter_files() -> list[Path]:
    files: list[Path] = []
    for root_name in SCAN_ROOTS:
        root = ROOT / root_name
        if root.is_file():
            files.append(root)
            continue
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if path.suffix in {".zig", ".md"} and path.is_file():
                files.append(path)
    return sorted(files)


def line_number(lines: list[str], index: int) -> int:
    return sum(line.count("\n") for line in lines[:index]) + 1


def run_self_tests() -> None:
    unsafe = [
        "const watch = try manager.watchFile(\"log.txt\", null);\n",
        "defer watch.deinit();\n",
    ]
    safe = [
        "const watch = try manager.watchFile(\"log.txt\", null);\n",
        "defer _ = manager.unwatchFile(watch);\n",
    ]
    low_level = [
        "const watch = try FileWatchContext.init(alloc, \"log.txt\", &queue, 1, null);\n",
        "defer watch.deinit();\n",
    ]
    if not manager_owned_direct_deinit_violations(unsafe, "fixture"):
        raise AssertionError("manager-owned direct deinit fixture was not detected")
    if manager_owned_direct_deinit_violations(safe, "fixture"):
        raise AssertionError("manager cleanup fixture should not be rejected")
    if manager_owned_direct_deinit_violations(low_level, "fixture"):
        raise AssertionError("low-level context ownership fixture should not be rejected")


def manager_owned_direct_deinit_violations(lines: list[str], rel: str) -> list[str]:
    violations: list[str] = []
    live_manager_owned: dict[str, tuple[str, int]] = {}

    for idx, line in enumerate(lines):
        assignment = MANAGER_OWNED_ASSIGNMENT.search(line)
        if assignment:
            live_manager_owned[assignment.group("name")] = (assignment.group("factory"), idx)

        for deinit in DIRECT_DEINIT.finditer(line):
            name = deinit.group("name")
            if name not in live_manager_owned:
                continue
            factory, assign_idx = live_manager_owned[name]
            replacement = "unwatchFile" if factory == "watchFile" else "disconnectFromServer"
            violations.append(
                f"{rel}:{line_number(lines, idx)}: `{name}` was returned by `{factory}` on line "
                f"{line_number(lines, assign_idx)}; use manager/application `{replacement}({name})` "
                "instead of direct `deinit()`"
            )

    return violations


def main() -> int:
    run_self_tests()
    violations: list[str] = []
    files = iter_files()

    for path in files:
        text = path.read_text(encoding="utf-8")
        rel = str(path.relative_to(ROOT))
        lines = text.splitlines(keepends=True)
        violations.extend(manager_owned_direct_deinit_violations(lines, rel))

    io_events = ROOT / "src" / "event" / "io_events.zig"
    text = io_events.read_text(encoding="utf-8")
    for match in IDEMPOTENT_IO_CONTEXT_DEINIT.finditer(text):
        violations.append(
            f"src/event/io_events.zig:{text.count(chr(10), 0, match.start()) + 1}: "
            "self-destroying I/O context deinit docs must not claim idempotence"
        )

    if violations:
        sys.stderr.write("I/O event ownership documentation issue(s) found:\n")
        for violation in violations:
            sys.stderr.write(f"  - {violation}\n")
        return 1

    print(f"checked I/O event ownership docs in {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
