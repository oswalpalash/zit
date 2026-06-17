#!/usr/bin/env python3
"""Repeat deterministic visual captures and build an SVG contact sheet.

The real-world examples and widget gallery render one deterministic frame. This
script runs each target multiple times, compares the raw frame output, and writes
all captures to a contact sheet so visual review can catch layout drift.
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


DEFAULT_TARGETS = [
    "htop-clone",
    "file-manager",
    "text-editor",
    "dashboard-demo",
    "widget-gallery",
    "widget-gallery-extended",
]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def safe_name(target: str) -> str:
    return target.replace("/", "-").replace(" ", "-")


def capture_target(root: Path, target: str) -> bytes:
    env = os.environ.copy()
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")
    proc = subprocess.run(
        ["zig", "build", target],
        cwd=root,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout.decode("utf-8", errors="replace"))
        raise RuntimeError(f"`zig build {target}` failed with exit code {proc.returncode}")
    return proc.stdout


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


def render_png_contact_sheet(out_dir: Path, targets: Iterable[str], count: int, captures: dict[str, list[bytes]]) -> Path | None:
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
            lines = capture.decode("utf-8", errors="replace").splitlines()
            draw.rectangle((x, y, x + panel_w, y + panel_h), fill=(12, 14, 18), outline=(47, 54, 66))
            draw.text((x + 8, y + 8), f"{target} #{run_index}", font=title_font, fill=(125, 211, 252))
            for line_index, line in enumerate(lines):
                draw.text((x + 8, y + 8 + cell_h + line_index * cell_h), line, font=font, fill=(229, 231, 235))
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
    args = parser.parse_args()

    if args.count < 2:
        parser.error("--count must be at least 2")

    root = repo_root()
    targets = args.targets or DEFAULT_TARGETS
    out_dir = args.out_dir if args.out_dir.is_absolute() else root / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    captures: dict[str, list[bytes]] = {}
    manifest: dict[str, object] = {"count": args.count, "targets": {}}

    for target in targets:
        target_captures: list[bytes] = []
        target_dir = out_dir / safe_name(target)
        target_dir.mkdir(parents=True, exist_ok=True)
        print(f"capturing {target} x{args.count}")
        for run_index in range(1, args.count + 1):
            data = capture_target(root, target)
            target_captures.append(data)
            (target_dir / f"{run_index:02d}.txt").write_bytes(data)

        expected = target_captures[0]
        for run_index, data in enumerate(target_captures[1:], start=2):
            if data != expected:
                sys.stderr.write(f"visual capture changed for {target} between runs 1 and {run_index}\n")
                sys.stderr.write(first_diff(expected, data, target, run_index) + "\n")
                return 1

        digest = hashlib.sha256(expected).hexdigest()
        manifest["targets"][target] = {
            "sha256": digest,
            "bytes": len(expected),
            "frames": [str(target_dir / f"{idx:02d}.txt") for idx in range(1, args.count + 1)],
        }
        captures[target] = target_captures
        print(f"  stable sha256={digest[:12]}")

    contact_sheet = render_contact_sheet(out_dir, targets, args.count, captures)
    png_contact_sheet = render_png_contact_sheet(out_dir, targets, args.count, captures)
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
