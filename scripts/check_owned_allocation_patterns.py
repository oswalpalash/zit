#!/usr/bin/env python3
"""Reject owned-allocation patterns that are not transactional.

Public widgets commonly take ownership of duplicated strings. Two patterns are
especially error-prone:

- appending ``try allocator.dupe(...)`` directly into a collection, which leaks
  the duplicate if the append allocation fails;
- freeing an owned field before assigning a replacement from a fallible
  duplicate allocation, which loses the old value on ``OutOfMemory``.
- allocating a widget/object with ``allocator.create`` and then duplicating
  owned data before either ``errdefer allocator.destroy(self)`` or
  ``errdefer self.deinit()`` has been installed.

Use reserve-before-duplicate/append helpers, ``errdefer`` cleanup, or
duplicate-before-free replacement instead.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = ("src", "examples", "docs", "README.md")

APPEND_DUPLICATE = re.compile(
    r"\.(?:append|insert)\s*\([^;\n]*try\s+(?:self\.)?allocator\.dupe\s*\(",
)
FREE_BEFORE_DUPLICATE = re.compile(
    r"(?:self\.)?allocator\.free\(\s*self\.(?P<free_field>[A-Za-z_][A-Za-z0-9_]*)\s*\)\s*;\s*"
    r"self\.(?P<assign_field>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*try\s+(?:self\.)?allocator\.dupe\s*\(",
    re.DOTALL,
)
SELF_CREATE = re.compile(
    r"const\s+self\s*=\s*try\s+allocator\.create\s*\([^;]+;\s*",
)
SELF_INIT = re.compile(r"\bself\.\*\s*=")


def unsafe_owned_allocation_before_self_init(text: str, init_start: int) -> bool:
    """Return true when fallible owned data is copied before self is initialized."""
    init_match = SELF_INIT.search(text, init_start)
    if init_match is None:
        return False

    init_window = text[init_start:init_match.start()]
    if "try allocator.dupe" not in init_window:
        return False
    return "errdefer allocator.destroy(self)" not in init_window


def run_self_tests() -> None:
    def create_end(sample: str) -> int:
        match = SELF_CREATE.search(sample)
        if match is None:
            raise AssertionError("self-test fixture did not match SELF_CREATE")
        return match.end()

    unsafe = """
pub fn init(allocator: std.mem.Allocator, text: []const u8) !*Widget {
    const self = try allocator.create(Widget);
    const text_copy = try allocator.dupe(u8, text);
    self.* = .{ .text = text_copy };
    return self;
}
"""
    safe_destroy = """
pub fn init(allocator: std.mem.Allocator, text: []const u8) !*Widget {
    const self = try allocator.create(Widget);
    errdefer allocator.destroy(self);
    const text_copy = try allocator.dupe(u8, text);
    self.* = .{ .text = text_copy };
    return self;
}
"""
    safe_after_init = """
pub fn init(allocator: std.mem.Allocator, text: []const u8) !*Widget {
    const self = try allocator.create(Widget);
    self.* = .{ .text = "" };
    errdefer self.deinit();
    const text_copy = try allocator.dupe(u8, text);
    self.text = text_copy;
    return self;
}
"""
    if not unsafe_owned_allocation_before_self_init(unsafe, create_end(unsafe)):
        raise AssertionError("unsafe self init allocation pattern was not detected")
    if unsafe_owned_allocation_before_self_init(safe_destroy, create_end(safe_destroy)):
        raise AssertionError("allocator.destroy errdefer should satisfy self init cleanup")
    if unsafe_owned_allocation_before_self_init(safe_after_init, create_end(safe_after_init)):
        raise AssertionError("owned allocation after self init should not trip pre-init cleanup check")


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


def line_no(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def main() -> int:
    run_self_tests()
    violations: list[str] = []
    files = iter_files()
    for path in files:
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)

        for match in APPEND_DUPLICATE.finditer(text):
            violations.append(
                f"{rel}:{line_no(text, match.start())}: reserve collection capacity before duplicating owned data, "
                "or use an errdefer-cleaned temporary before append/insert"
            )

        for match in FREE_BEFORE_DUPLICATE.finditer(text):
            if match.group("free_field") != match.group("assign_field"):
                continue
            field = match.group("free_field")
            violations.append(
                f"{rel}:{line_no(text, match.start())}: duplicate replacement for `self.{field}` before freeing "
                "the existing value"
            )

        for match in SELF_CREATE.finditer(text):
            if not unsafe_owned_allocation_before_self_init(text, match.end()):
                continue
            violations.append(
                f"{rel}:{line_no(text, match.start())}: install `errdefer allocator.destroy(self)` before "
                "fallible owned allocations that run before `self.*` initialization"
            )

    if violations:
        sys.stderr.write("non-transactional owned allocation pattern(s) found:\n")
        for violation in violations:
            sys.stderr.write(f"  - {violation}\n")
        return 1

    print(f"checked owned allocation patterns in {len(files)} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
