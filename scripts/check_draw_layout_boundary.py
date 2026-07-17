#!/usr/bin/env python3
"""Reject layout, allocation, and byte-clipping work from widget draws.

Layout publishes geometry, dirty regions, and accessibility bounds. Calling it
from draw makes render cost stateful and can republish bounds every frame.
Allocating from draw adds frame-time latency and makes rendering fail after
successful widget setup. Draw callbacks must consume prepared geometry and
retained storage. Arbitrary text must be clipped by terminal-cell width so draw
paths cannot split UTF-8 or disagree with rendered geometry.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = (ROOT / "src" / "widget", ROOT / "examples")
DRAW_ASSIGNMENT = re.compile(r"\.draw\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*,")
LAYOUT_CALL = re.compile(r"\.\s*layout\s*\(")
DRAW_ALLOCATION = re.compile(
    r"\bstd\.fmt\.allocPrint\s*\("
    r"|\b(?:self\.)?allocator\.(?:alloc(?:WithOptions|Sentinel)?|alignedAlloc|create|dupeZ?|realloc|remap|resize)\s*\("
    r"|\.(?:append|insert|resize|addOne|addManyAsArray|ensure(?:Total|Unused)Capacity(?:Precise)?|initCapacity|toOwnedSlice)\s*\(\s*self\.allocator\b",
)
BYTE_PREFIX_CLIP = re.compile(r"\[\s*0\s*\.\.\s*@min\s*\([^;\n]*?\.len\b")
BYTE_CLIP_BOUND = re.compile(
    r"\b(?:const|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"[^;]*?@min\s*\([^;]*?\.len\b[^;]*?;",
)
BYTE_INDEX_LOOP = re.compile(
    r"\bfor\s*\(\s*([^,\n]+?)\s*,\s*0\s*\.\.\s*\)\s*\|",
)
ARBITRARY_TEXT_MEMBER = re.compile(
    r"\.\s*(?:title|text|header|label|message|body|option|step)\b",
)
ASSIGNMENT = re.compile(
    r"\b(?:(?:const|var)\s+)?([A-Za-z_][A-Za-z0-9_]*)"
    r"\s*(?::[^=;\n]+)?=\s*([^;\n]+);",
)
IDENTIFIER = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
SELF_CALL = re.compile(r"\bself\.([A-Za-z_][A-Za-z0-9_]*)\s*\(")
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


def indexed_text_iteration(masked: str, start: int, end: int) -> int | None:
    """Find indexed byte iteration over arbitrary text fields or their aliases."""
    body = masked[start:end]
    tainted: set[str] = set()
    assignments = list(ASSIGNMENT.finditer(body))

    changed = True
    while changed:
        changed = False
        for assignment in assignments:
            name, expression = assignment.groups()
            identifiers = set(IDENTIFIER.findall(expression))
            if ARBITRARY_TEXT_MEMBER.search(expression) or identifiers & tainted:
                if name not in tainted:
                    tainted.add(name)
                    changed = True

    for loop in BYTE_INDEX_LOOP.finditer(body):
        expression = loop.group(1)
        identifiers = set(IDENTIFIER.findall(expression))
        if ARBITRARY_TEXT_MEMBER.search(expression) or identifiers & tainted:
            return start + loop.start()
    return None


def violations_in(source: str) -> list[tuple[int, str, str]]:
    masked = mask_non_code(source)
    tests = test_ranges(masked)
    callbacks = {
        match.group(1)
        for match in DRAW_ASSIGNMENT.finditer(masked)
        if not in_ranges(match.start(), tests)
    }
    violations: list[tuple[int, str, str]] = []

    def find_forbidden_call(function: str, seen: set[str]) -> tuple[int, str] | None:
        if function in seen:
            return None
        seen.add(function)
        declaration = re.compile(rf"\bfn\s+{re.escape(function)}\s*\(")
        for match in declaration.finditer(masked):
            if in_ranges(match.start(), tests):
                continue
            start, end = body_range(masked, match.end())
            call = LAYOUT_CALL.search(masked, start, end)
            if call is not None:
                return (
                    call.start(),
                    "must consume geometry prepared by layout; do not call Widget.layout() from draw",
                )
            allocation = DRAW_ALLOCATION.search(masked, start, end)
            if allocation is not None:
                return (
                    allocation.start(),
                    "must remain allocation-free; prepare data and capacity outside draw",
                )
            byte_clip = BYTE_PREFIX_CLIP.search(masked, start, end)
            if byte_clip is not None:
                return (
                    byte_clip.start(),
                    "must clip arbitrary text by terminal cells; use render.clipTextToWidth instead of byte-prefix slicing",
                )
            for bound in BYTE_CLIP_BOUND.finditer(masked, start, end):
                prefix_slice = re.compile(
                    r"\[\s*0\s*\.\.\s*" + re.escape(bound.group(1)) + r"\s*\]"
                ).search(masked, bound.end(), end)
                if prefix_slice is not None:
                    return (
                        prefix_slice.start(),
                        "must clip arbitrary text by terminal cells; use render.clipTextToWidth instead of byte-prefix slicing",
                    )
            byte_iteration = indexed_text_iteration(masked, start, end)
            if byte_iteration is not None:
                return (
                    byte_iteration,
                    "must not iterate arbitrary UTF-8 as indexed bytes; clip and draw by terminal cells",
                )
            for helper_call in SELF_CALL.finditer(masked, start, end):
                indirect = find_forbidden_call(helper_call.group(1), seen)
                if indirect is not None:
                    return indirect
        return None

    for callback in sorted(callbacks):
        violation = find_forbidden_call(callback, set())
        if violation is not None:
            index, message = violation
            violations.append((index, callback, message))
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
    indirect_violation = """
const vtable = VTable{ .draw = renderFrame, };
fn renderFrame(_: *anyopaque) !void { try self.prepareFrame(); }
fn prepareFrame(self: *Widget) !void { try self.child.layout(rect); }
"""
    allocation_violation = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void { const text = try std.fmt.allocPrint(self.allocator, "{s}", .{value}); }
"""
    indirect_allocation = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void { try self.collectVisible(); }
fn collectVisible(self: *Widget) !void { try self.visible.append(self.allocator, item); }
"""
    byte_clip_violation = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void { renderer.drawStr(x, y, self.label[0..@min(self.label.len, width)]); }
"""
    indirect_byte_clip = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void {
    const label_len = @as(u16, @intCast(@min(self.label.len, width)));
    renderer.drawStr(x, y, self.label[0..label_len]);
}
"""
    byte_iteration_violation = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void {
    for (self.item.title, 0..) |byte, index| renderer.drawChar(x + index, y, byte);
}
"""
    aliased_byte_iteration = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void {
    var visible = self.label;
    if (selected) visible = self.item.text;
    for (visible, 0..) |byte, index| renderer.drawChar(x + index, y, byte);
}
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
    retained_storage = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void { self.visible.appendAssumeCapacity(item); }
"""
    cell_clipping = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void {
    const clipped = render.clipTextToWidth(self.label, width);
    renderer.drawStr(x, y, clipped.text);
    const fixed = buffer[0..len];
}
"""
    generated_ascii_iteration = """
const vtable = VTable{ .draw = drawFn, };
fn drawFn(_: *anyopaque) !void {
    var buffer: [5]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buffer, "{d}%", .{progress}) catch "";
    for (text, 0..) |byte, index| renderer.drawChar(x + index, y, byte);
}
"""
    if not violations_in(violation):
        raise AssertionError("draw-time layout was not detected")
    if not violations_in(indirect_violation):
        raise AssertionError("indirect draw-time layout was not detected")
    if not violations_in(allocation_violation):
        raise AssertionError("draw-time allocation was not detected")
    if not violations_in(indirect_allocation):
        raise AssertionError("indirect draw-time allocation was not detected")
    if not violations_in(byte_clip_violation):
        raise AssertionError("draw-time byte clipping was not detected")
    if not violations_in(indirect_byte_clip):
        raise AssertionError("indirect draw-time byte clipping was not detected")
    if not violations_in(byte_iteration_violation):
        raise AssertionError("draw-time indexed text iteration was not detected")
    if not violations_in(aliased_byte_iteration):
        raise AssertionError("aliased draw-time indexed text iteration was not detected")
    for source in (
        clean,
        test_only,
        literal_only,
        retained_storage,
        cell_clipping,
        generated_ascii_iteration,
    ):
        if violations_in(source):
            raise AssertionError("clean or test-only draw code was rejected")


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
        for index, callback, message in found:
            rel = path.relative_to(ROOT)
            violations.append(
                f"{rel}:{line_number(source, index)}: {callback} {message}"
            )

    if violations:
        sys.stderr.write("draw boundary violation(s) found:\n")
        for violation in violations:
            sys.stderr.write(f"  - {violation}\n")
        return 1

    print(
        f"checked draw layout/allocation/text-geometry boundaries for {callback_count} "
        f"callback name(s) in {len(files)} file(s)"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, RuntimeError) as err:
        sys.stderr.write(f"draw boundary check failed: {err}\n")
        raise SystemExit(1)
