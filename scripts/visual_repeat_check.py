#!/usr/bin/env python3
"""Repeat deterministic visual captures and build an SVG contact sheet.

The real-world examples and widget galleries are interactive by default. This
script runs each target in explicit ``--snapshot`` mode multiple times, compares
the raw frame output, and writes all captures to a contact sheet so visual review
can catch layout drift. It also enforces plain-text frame invariants that keep
public screenshots reviewable: valid UTF-8, newline-terminated output, no
terminal control bytes, rectangular rows, and bounded dimensions.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import html
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:  # pragma: no cover - optional local inspection dependency.
    Image = None
    ImageDraw = None
    ImageFont = None

try:
    from make_screenshots import TerminalEmulator
except Exception:  # pragma: no cover - visual PNG color rendering is optional.
    TerminalEmulator = None


DEFAULT_TARGETS = [
    "htop-clone",
    "file-manager",
    "text-editor",
    "dashboard-demo",
    "system-monitor",
    "file-manager-example",
    "widget-showcase",
    "widget-gallery",
    "widget-gallery-extended",
    "widget-gallery-layouts",
]

DEFAULT_MAX_COLS = 160
DEFAULT_MAX_ROWS = 80


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def safe_name(target: str) -> str:
    return target.replace("/", "-").replace(" ", "-")


def binary_name(target: str) -> str:
    suffix = ".exe" if os.name == "nt" else ""
    return target.replace("-", "_") + suffix


def ensure_binaries(root: Path) -> None:
    env = os.environ.copy()
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")
    proc = subprocess.run(
        ["zig", "build"],
        cwd=root,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout.decode("utf-8", errors="replace"))
        raise RuntimeError(f"`zig build` failed with exit code {proc.returncode}")


def capture_target(root: Path, target: str) -> bytes:
    env = os.environ.copy()
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")
    binary = root / "zig-out" / "bin" / binary_name(target)
    proc = subprocess.run(
        [str(binary), "--snapshot"],
        cwd=root,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout.decode("utf-8", errors="replace"))
        raise RuntimeError(f"`{binary} --snapshot` failed with exit code {proc.returncode}")
    return proc.stdout


def capture_ansi_target(root: Path, target: str) -> bytes:
    env = os.environ.copy()
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")
    binary = root / "zig-out" / "bin" / binary_name(target)
    proc = subprocess.run(
        [str(binary), "--ansi-snapshot"],
        cwd=root,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout.decode("utf-8", errors="replace"))
        raise RuntimeError(f"`{binary} --ansi-snapshot` failed with exit code {proc.returncode}")
    if not proc.stdout:
        raise RuntimeError(f"`{binary} --ansi-snapshot` produced no output")
    return proc.stdout


def ansi_visible_lines(capture: bytes, cols: int, rows: int) -> list[str]:
    if TerminalEmulator is None:
        return []

    screen = TerminalEmulator(cols, rows)
    screen.feed(capture)
    return ["".join(cell.ch for cell in row) for row in screen.cells]


def validate_ansi_capture_quality(capture: bytes, text_capture: bytes, target: str) -> None:
    try:
        capture.decode("utf-8")
    except UnicodeDecodeError as err:
        raise RuntimeError(f"{target}: ANSI snapshot is not valid UTF-8: {err}") from err

    if b"\x00" in capture:
        raise RuntimeError(f"{target}: ANSI snapshot contains NUL byte(s)")
    if b"\x1b[" not in capture and b"\x1b]" not in capture:
        raise RuntimeError(
            f"{target}: --ansi-snapshot did not emit terminal escape sequences; "
            "use the renderer-backed frame so PNG visual review sees real styling"
        )

    if TerminalEmulator is None:
        return

    expected_lines = text_capture.decode("utf-8").splitlines()
    cols = max((len(line) for line in expected_lines), default=1)
    rows = max(len(expected_lines), 1)
    actual_lines = ansi_visible_lines(capture, cols, rows)
    if actual_lines != expected_lines:
        diff = "\n".join(
            list(
                difflib.unified_diff(
                    expected_lines,
                    actual_lines,
                    fromfile=f"{target}-snapshot",
                    tofile=f"{target}-ansi-visible",
                    lineterm="",
                    n=3,
                )
            )[:80]
        )
        raise RuntimeError(
            f"{target}: ANSI snapshot visible cells do not match the plain snapshot; "
            f"PNG review would inspect a different frame\n{diff}"
        )


def first_diff(expected: bytes, actual: bytes, target: str, run_index: int) -> str:
    expected_lines = expected.decode("utf-8", errors="replace").splitlines()
    actual_lines = actual.decode("utf-8", errors="replace").splitlines()
    diff = difflib.unified_diff(
        expected_lines,
        actual_lines,
        fromfile=f"{target}-01",
        tofile=f"{target}-{run_index:02d}",
        lineterm="",
        n=3,
    )
    return "\n".join(list(diff)[:80])


def text_dimensions(capture: bytes) -> tuple[int, int]:
    lines = capture.decode("utf-8", errors="replace").splitlines()
    return max((len(line) for line in lines), default=1), max(len(lines), 1)


def capture_lines(capture: bytes, target: str) -> list[str]:
    try:
        text = capture.decode("utf-8")
    except UnicodeDecodeError as err:
        raise RuntimeError(f"{target}: snapshot is not valid UTF-8: {err}") from err

    if not text:
        raise RuntimeError(f"{target}: snapshot is empty")
    if not text.endswith("\n"):
        raise RuntimeError(f"{target}: snapshot must end with a newline")

    forbidden_bytes = {
        b"\x00": "NUL",
        b"\x1b": "ESC/ANSI",
        b"\r": "carriage return",
        b"\t": "tab",
    }
    for needle, label in forbidden_bytes.items():
        if needle in capture:
            raise RuntimeError(f"{target}: snapshot contains {label} byte(s); visual-repeat requires plain text")

    for index, ch in enumerate(text):
        if ch == "\n":
            continue
        if ord(ch) < 32:
            raise RuntimeError(f"{target}: snapshot contains control character U+{ord(ch):04X} at byte/char offset {index}")

    lines = text.splitlines()
    if not lines:
        raise RuntimeError(f"{target}: snapshot has no rows")
    return lines


def validate_capture_quality(capture: bytes, target: str, max_cols: int, max_rows: int) -> tuple[int, int]:
    lines = capture_lines(capture, target)
    widths = {len(line) for line in lines}
    if len(widths) != 1:
        preview = ", ".join(str(width) for width in sorted(widths)[:8])
        raise RuntimeError(f"{target}: snapshot rows are not rectangular; observed widths: {preview}")

    cols = widths.pop()
    rows = len(lines)
    if cols == 0:
        raise RuntimeError(f"{target}: snapshot has zero-width rows")
    if cols > max_cols:
        raise RuntimeError(f"{target}: snapshot width {cols} exceeds --max-cols={max_cols}")
    if rows > max_rows:
        raise RuntimeError(f"{target}: snapshot height {rows} exceeds --max-rows={max_rows}")
    return cols, rows


def render_panel(target: str, run_index: int, capture: bytes, x: int, y: int, width: int, cell_h: int) -> list[str]:
    lines = capture.decode("utf-8", errors="replace").splitlines()
    panel_height = (len(lines) + 2) * cell_h + 16
    out = [
        f'<rect x="{x}" y="{y}" width="{width}" height="{panel_height}" fill="#0c0e12" stroke="#2f3642" stroke-width="1"/>',
        f'<text x="{x + 8}" y="{y + 8}" font-family="Menlo, Consolas, monospace" font-size="11" fill="#7dd3fc" dominant-baseline="hanging">{html.escape(target)} #{run_index}</text>',
    ]
    text_y = y + 8 + cell_h
    for offset, line in enumerate(lines):
        out.append(
            f'<text x="{x + 8}" y="{text_y + offset * cell_h}" xml:space="preserve" '
            f'font-family="Menlo, Consolas, monospace" font-size="10" fill="#e5e7eb" '
            f'dominant-baseline="hanging">{html.escape(line)}</text>'
        )
    return out


def render_contact_sheet(out_dir: Path, targets: Iterable[str], count: int, captures: dict[str, list[bytes]]) -> Path:
    cell_w = 6
    cell_h = 13
    gap = 14
    target_list = list(targets)
    max_cols = 1
    max_rows = 1
    for target in target_list:
        for capture in captures[target]:
            cols, rows = text_dimensions(capture)
            max_cols = max(max_cols, cols)
            max_rows = max(max_rows, rows)

    panel_w = max_cols * cell_w + 16
    panel_h = (max_rows + 2) * cell_h + 16
    sheet_w = gap + count * (panel_w + gap)
    sheet_h = gap + len(target_list) * (panel_h + gap)

    svg: list[str] = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{sheet_w}" height="{sheet_h}" viewBox="0 0 {sheet_w} {sheet_h}">',
        f'<rect x="0" y="0" width="{sheet_w}" height="{sheet_h}" fill="#05070a"/>',
    ]

    y = gap
    for target in target_list:
        x = gap
        for idx, capture in enumerate(captures[target], start=1):
            svg.extend(render_panel(target, idx, capture, x, y, panel_w, cell_h))
            x += panel_w + gap
        y += panel_h + gap

    svg.append("</svg>")
    contact_sheet = out_dir / "contact-sheet.svg"
    contact_sheet.write_text("\n".join(svg), encoding="utf-8")
    return contact_sheet


def render_terminal_panel(
    draw: "ImageDraw.ImageDraw",
    font: "ImageFont.ImageFont",
    title_font: "ImageFont.ImageFont",
    x: int,
    y: int,
    panel_w: int,
    panel_h: int,
    cell_w: int,
    cell_h: int,
    target: str,
    run_index: int,
    text_capture: bytes,
    ansi_capture: bytes | None,
) -> None:
    draw.rectangle((x, y, x + panel_w, y + panel_h), fill=(12, 14, 18), outline=(47, 54, 66))
    draw.text((x + 8, y + 8), f"{target} #{run_index}", font=title_font, fill=(125, 211, 252))

    text_lines = text_capture.decode("utf-8", errors="replace").splitlines()
    if ansi_capture is None or TerminalEmulator is None:
        for line_index, line in enumerate(text_lines):
            draw.text((x + 8, y + 8 + cell_h + line_index * cell_h), line, font=font, fill=(229, 231, 235))
        return

    cols = max((len(line) for line in text_lines), default=1)
    rows = max(len(text_lines), 1)
    screen = TerminalEmulator(cols, rows)
    screen.feed(ansi_capture)

    origin_x = x + 8
    origin_y = y + 8 + cell_h
    for row_index, row in enumerate(screen.cells):
        yy = origin_y + row_index * cell_h
        col = 0
        while col < screen.cols:
            start = col
            bg = row[col].bg
            while col < screen.cols and row[col].bg == bg:
                col += 1
            draw.rectangle(
                (origin_x + start * cell_w, yy, origin_x + col * cell_w, yy + cell_h),
                fill=bg,
            )

        for col_index, cell in enumerate(row):
            if cell.ch == " ":
                continue
            draw.text(
                (origin_x + col_index * cell_w, yy),
                cell.ch,
                font=font,
                fill=cell.fg,
            )
            if cell.bold:
                draw.text(
                    (origin_x + col_index * cell_w + 1, yy),
                    cell.ch,
                    font=font,
                    fill=cell.fg,
                )


def render_png_contact_sheet(
    out_dir: Path,
    targets: Iterable[str],
    count: int,
    captures: dict[str, list[bytes]],
    ansi_captures: dict[str, list[bytes]] | None = None,
) -> Path | None:
    if Image is None or ImageDraw is None or ImageFont is None:
        return None

    font = None
    title_font = None
    for path in (
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/SFNSMono.ttf",
        "/Library/Fonts/Menlo.ttf",
    ):
        try:
            font = ImageFont.truetype(path, 10)
            title_font = ImageFont.truetype(path, 11)
            break
        except Exception:
            pass
    if font is None:
        font = ImageFont.load_default()
        title_font = font

    cell_w = max(6, font.getbbox("M")[2] - font.getbbox("M")[0])
    cell_h = max(13, font.getbbox("M")[3] - font.getbbox("M")[1] + 4)
    gap = 14
    target_list = list(targets)
    max_cols = 1
    max_rows = 1
    for target in target_list:
        for capture in captures[target]:
            cols, rows = text_dimensions(capture)
            max_cols = max(max_cols, cols)
            max_rows = max(max_rows, rows)

    panel_w = max_cols * cell_w + 16
    panel_h = (max_rows + 2) * cell_h + 16
    sheet_w = gap + count * (panel_w + gap)
    sheet_h = gap + len(target_list) * (panel_h + gap)
    sheet = Image.new("RGB", (sheet_w, sheet_h), (5, 7, 10))
    draw = ImageDraw.Draw(sheet)

    y = gap
    for target in target_list:
        x = gap
        for run_index, capture in enumerate(captures[target], start=1):
            ansi_capture = None
            if ansi_captures is not None and target in ansi_captures:
                ansi_capture = ansi_captures[target][run_index - 1]
            render_terminal_panel(
                draw,
                font,
                title_font,
                x,
                y,
                panel_w,
                panel_h,
                cell_w,
                cell_h,
                target,
                run_index,
                capture,
                ansi_capture,
            )
            x += panel_w + gap
        y += panel_h + gap

    contact_sheet = out_dir / "contact-sheet.png"
    sheet.save(contact_sheet)
    return contact_sheet


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=4, help="captures per target")
    parser.add_argument("--out-dir", type=Path, default=Path("zig-out/visual-repeat"), help="output directory")
    parser.add_argument("--target", action="append", dest="targets", help="target to capture; may be repeated")
    parser.add_argument("--max-cols", type=int, default=DEFAULT_MAX_COLS, help="maximum allowed snapshot width")
    parser.add_argument("--max-rows", type=int, default=DEFAULT_MAX_ROWS, help="maximum allowed snapshot height")
    args = parser.parse_args()

    if args.count < 2:
        parser.error("--count must be at least 2")
    if args.max_cols < 1:
        parser.error("--max-cols must be positive")
    if args.max_rows < 1:
        parser.error("--max-rows must be positive")

    root = repo_root()
    targets = args.targets or DEFAULT_TARGETS
    out_dir = args.out_dir if args.out_dir.is_absolute() else root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    captures: dict[str, list[bytes]] = {}
    ansi_captures: dict[str, list[bytes]] = {}
    manifest: dict[str, object] = {"count": args.count, "targets": {}}

    ensure_binaries(root)

    for target in targets:
        target_captures: list[bytes] = []
        target_ansi_captures: list[bytes] = []
        target_dir = out_dir / safe_name(target)
        target_dir.mkdir(parents=True, exist_ok=True)
        print(f"capturing {target} x{args.count}")
        for run_index in range(1, args.count + 1):
            data = capture_target(root, target)
            cols, rows = validate_capture_quality(data, target, args.max_cols, args.max_rows)
            target_captures.append(data)
            (target_dir / f"{run_index:02d}.txt").write_bytes(data)

            ansi_data = capture_ansi_target(root, target)
            validate_ansi_capture_quality(ansi_data, data, target)
            target_ansi_captures.append(ansi_data)
            (target_dir / f"{run_index:02d}.ansi").write_bytes(ansi_data)

        expected = target_captures[0]
        for run_index, data in enumerate(target_captures[1:], start=2):
            if data != expected:
                sys.stderr.write(f"visual capture changed for {target} between runs 1 and {run_index}\n")
                sys.stderr.write(first_diff(expected, data, target, run_index) + "\n")
                return 1

        expected_ansi = target_ansi_captures[0]
        for run_index, data in enumerate(target_ansi_captures[1:], start=2):
            if data != expected_ansi:
                sys.stderr.write(f"ANSI visual capture changed for {target} between runs 1 and {run_index}\n")
                return 1

        digest = hashlib.sha256(expected).hexdigest()
        ansi_digest = hashlib.sha256(expected_ansi).hexdigest()
        manifest["targets"][target] = {
            "sha256": digest,
            "ansi_sha256": ansi_digest,
            "bytes": len(expected),
            "ansi_bytes": len(expected_ansi),
            "cols": cols,
            "rows": rows,
            "rectangular": True,
            "frames": [str(target_dir / f"{idx:02d}.txt") for idx in range(1, args.count + 1)],
            "ansi_frames": [str(target_dir / f"{idx:02d}.ansi") for idx in range(1, args.count + 1)],
        }
        captures[target] = target_captures
        ansi_captures[target] = target_ansi_captures
        print(f"  stable sha256={digest[:12]}")

    contact_sheet = render_contact_sheet(out_dir, targets, args.count, captures)
    png_contact_sheet = render_png_contact_sheet(out_dir, targets, args.count, captures, ansi_captures)
    manifest["contact_sheet"] = str(contact_sheet)
    if png_contact_sheet is not None:
        manifest["png_contact_sheet"] = str(png_contact_sheet)
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"contact sheet: {contact_sheet}")
    if png_contact_sheet is not None:
        print(f"png contact sheet: {png_contact_sheet}")
    print(f"manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
