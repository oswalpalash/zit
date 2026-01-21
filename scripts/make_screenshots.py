#!/usr/bin/env python3
"""
Lightweight terminal capture utility for Zit demos.

It opens a pseudo-TTY, runs the demo for a short window, keeps the last
frame of terminal output, and renders it to an SVG without external
dependencies. Suitable for environments without vhs/asciinema/termtosvg.
"""

from __future__ import annotations

import argparse
import html
import fcntl
import os
import pty
import select
import shlex
import signal
import struct
import subprocess
import termios
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

# Palette approximating xterm defaults.
BASE_COLORS = [
    (0, 0, 0),  # 0 black
    (205, 49, 49),  # 1 red
    (13, 188, 121),  # 2 green
    (229, 229, 16),  # 3 yellow
    (36, 114, 200),  # 4 blue
    (188, 63, 188),  # 5 magenta
    (17, 168, 205),  # 6 cyan
    (229, 229, 229),  # 7 white
    (102, 102, 102),  # 8 bright black
    (241, 76, 76),  # 9 bright red
    (35, 209, 139),  # 10 bright green
    (245, 245, 67),  # 11 bright yellow
    (59, 142, 234),  # 12 bright blue
    (214, 112, 214),  # 13 bright magenta
    (41, 184, 219),  # 14 bright cyan
    (255, 255, 255),  # 15 bright white
]


def color_from_index(idx: int) -> Tuple[int, int, int]:
    if idx < 0:
        return BASE_COLORS[7]
    if idx < 16:
        return BASE_COLORS[idx]
    if idx < 232:
        v = idx - 16
        r = (v // 36) % 6
        g = (v // 6) % 6
        b = v % 6
        def level(x: int) -> int:
            return 55 + x * 40 if x else 0
        return (level(r), level(g), level(b))
    v = 8 + (idx - 232) * 10
    v = max(0, min(255, v))
    return (v, v, v)


@dataclass
class Cell:
    ch: str = " "
    fg: Tuple[int, int, int] = (230, 230, 230)
    bg: Tuple[int, int, int] = (10, 12, 16)
    bold: bool = False


class TerminalEmulator:
    def __init__(self, cols: int, rows: int):
        self.cols = cols
        self.rows = rows
        self.reset()

    def reset(self) -> None:
        self.cells: List[List[Cell]] = [
            [Cell() for _ in range(self.cols)] for _ in range(self.rows)
        ]
        self.cx = 0
        self.cy = 0
        self.saved: Optional[Tuple[int, int]] = None
        self.current_fg = (230, 230, 230)
        self.current_bg = (10, 12, 16)
        self.bold = False
        self.state = "normal"
        self.csi_buf = ""
        self.osc_active = False

    def feed(self, data: bytes) -> None:
        i = 0
        while i < len(data):
            b = data[i]
            if self.state == "normal":
                if b == 0x1B:  # ESC
                    self.state = "esc"
                elif b == 0x0D:  # CR
                    self.cx = 0
                elif b == 0x0A:  # LF
                    self._newline()
                elif b == 0x08:  # BS
                    self.cx = max(0, self.cx - 1)
                elif b == 0x09:  # TAB
                    self.cx = min(self.cols - 1, ((self.cx // 8) + 1) * 8)
                elif b == 0x07:  # BEL
                    pass
                elif 0x20 <= b <= 0x7E or b >= 0xA0:
                    self._put_char(chr(b))
                i += 1
            elif self.state == "esc":
                if b == ord("["):
                    self.state = "csi"
                    self.csi_buf = ""
                elif b == ord("]"):
                    self.osc_active = True
                    self.state = "osc"
                else:
                    self.state = "normal"
                i += 1
            elif self.state == "osc":
                if b == 0x07:  # BEL terminates OSC
                    self.osc_active = False
                    self.state = "normal"
                elif b == 0x1B and i + 1 < len(data) and data[i + 1] == ord("\\"):
                    self.osc_active = False
                    self.state = "normal"
                    i += 1
                i += 1
            elif self.state == "csi":
                ch = chr(b)
                if "@" <= ch <= "~":
                    self._handle_csi(ch, self.csi_buf)
                    self.state = "normal"
                else:
                    self.csi_buf += ch
                i += 1

    def _newline(self) -> None:
        self.cx = 0
        self.cy += 1
        if self.cy >= self.rows:
            self.cy = self.rows - 1
            self._scroll(1)

    def _scroll(self, count: int) -> None:
        for _ in range(count):
            self.cells.pop(0)
            self.cells.append([Cell(fg=self.current_fg, bg=self.current_bg, bold=self.bold) for _ in range(self.cols)])

    def _put_char(self, ch: str) -> None:
        if self.cx >= self.cols:
            self._newline()
        if self.cy >= self.rows:
            self._scroll(1)
            self.cy = self.rows - 1
        self.cells[self.cy][self.cx] = Cell(ch=ch, fg=self.current_fg, bg=self.current_bg, bold=self.bold)
        self.cx += 1

    def _handle_csi(self, final: str, params_raw: str) -> None:
        private = params_raw.startswith("?")
        if private:
            params_raw = params_raw[1:]
        params = [p for p in params_raw.split(";") if p]
        ints = [int(p) if p.isdigit() else 0 for p in params] if params else []

        if final in ("H", "f"):
            row = ints[0] if len(ints) >= 1 else 1
            col = ints[1] if len(ints) >= 2 else 1
            self.cy = max(0, min(self.rows - 1, row - 1))
            self.cx = max(0, min(self.cols - 1, col - 1))
        elif final == "A":
            self.cy = max(0, self.cy - (ints[0] if ints else 1))
        elif final == "B":
            self.cy = min(self.rows - 1, self.cy + (ints[0] if ints else 1))
        elif final == "C":
            self.cx = min(self.cols - 1, self.cx + (ints[0] if ints else 1))
        elif final == "D":
            self.cx = max(0, self.cx - (ints[0] if ints else 1))
        elif final == "J":
            mode = ints[0] if ints else 0
            if mode == 2:
                self.reset()
        elif final == "K":
            mode = ints[0] if ints else 0
            if mode in (0, 1, 2):
                if mode == 0:
                    start, end = self.cx, self.cols
                elif mode == 1:
                    start, end = 0, self.cx + 1
                else:
                    start, end = 0, self.cols
                for x in range(start, min(end, self.cols)):
                    if 0 <= self.cy < self.rows:
                        self.cells[self.cy][x] = Cell(fg=self.current_fg, bg=self.current_bg, bold=self.bold)
        elif final == "m":
            self._apply_sgr(ints)
        elif final == "s":
            self.saved = (self.cx, self.cy)
        elif final == "u":
            if self.saved:
                self.cx, self.cy = self.saved
        else:
            # Ignore other sequences.
            pass

    def _apply_sgr(self, params: List[int]) -> None:
        if not params:
            params = [0]
        i = 0
        while i < len(params):
            p = params[i]
            if p == 0:
                self.current_fg = (230, 230, 230)
                self.current_bg = (10, 12, 16)
                self.bold = False
            elif p == 1:
                self.bold = True
            elif 30 <= p <= 37:
                self.current_fg = BASE_COLORS[p - 30]
            elif 90 <= p <= 97:
                self.current_fg = BASE_COLORS[p - 90 + 8]
            elif p == 39:
                self.current_fg = (230, 230, 230)
            elif 40 <= p <= 47:
                self.current_bg = BASE_COLORS[p - 40]
            elif 100 <= p <= 107:
                self.current_bg = BASE_COLORS[p - 100 + 8]
            elif p == 49:
                self.current_bg = (10, 12, 16)
            elif p in (38, 48):
                is_fg = p == 38
                if i + 1 < len(params) and params[i + 1] == 2 and i + 4 < len(params):
                    r, g, b = params[i + 2 : i + 5]
                    color = (r, g, b)
                    if is_fg:
                        self.current_fg = color
                    else:
                        self.current_bg = color
                    i += 4
                elif i + 1 < len(params) and params[i + 1] == 5 and i + 2 < len(params):
                    idx = params[i + 2]
                    color = color_from_index(idx)
                    if is_fg:
                        self.current_fg = color
                    else:
                        self.current_bg = color
                    i += 2
            i += 1


def fill_rect(screen: TerminalEmulator, x: int, y: int, w: int, h: int, ch: str, fg: Tuple[int, int, int], bg: Tuple[int, int, int], bold: bool = False) -> None:
    for yy in range(y, min(screen.rows, y + h)):
        for xx in range(x, min(screen.cols, x + w)):
            screen.cells[yy][xx] = Cell(ch=ch, fg=fg, bg=bg, bold=bold)


def draw_text(screen: TerminalEmulator, x: int, y: int, text: str, fg: Tuple[int, int, int], bg: Optional[Tuple[int, int, int]] = None, bold: bool = False) -> None:
    if not (0 <= y < screen.rows):
        return
    for i, ch in enumerate(text):
        xx = x + i
        if 0 <= xx < screen.cols:
            cell_bg = bg if bg is not None else screen.cells[y][xx].bg
            screen.cells[y][xx] = Cell(ch=ch, fg=fg, bg=cell_bg, bold=bold)


def draw_box(screen: TerminalEmulator, x: int, y: int, w: int, h: int, fg: Tuple[int, int, int], bg: Tuple[int, int, int], title: Optional[str] = None) -> None:
    if w <= 1 or h <= 1:
        return
    fill_rect(screen, x, y, w, h, " ", fg, bg)
    for xx in range(x, min(screen.cols, x + w)):
        for yy in (y, min(screen.rows - 1, y + h - 1)):
            screen.cells[yy][xx] = Cell(ch="-" if yy in (y, y + h - 1) else " ", fg=fg, bg=bg, bold=False)
    for yy in range(y, min(screen.rows, y + h)):
        for xx in (x, min(screen.cols - 1, x + w - 1)):
            screen.cells[yy][xx] = Cell(ch="|" if xx in (x, x + w - 1) else " ", fg=fg, bg=bg, bold=False)
    screen.cells[y][x] = Cell(ch="+", fg=fg, bg=bg, bold=False)
    screen.cells[y][min(screen.cols - 1, x + w - 1)] = Cell(ch="+", fg=fg, bg=bg, bold=False)
    screen.cells[min(screen.rows - 1, y + h - 1)][x] = Cell(ch="+", fg=fg, bg=bg, bold=False)
    screen.cells[min(screen.rows - 1, y + h - 1)][min(screen.cols - 1, x + w - 1)] = Cell(ch="+", fg=fg, bg=bg, bold=False)
    if title:
        draw_text(screen, x + 2, y, f"[ {title} ]", fg, bg, bold=True)


def make_mock_system_monitor(rows: int, cols: int) -> TerminalEmulator:
    screen = TerminalEmulator(cols, rows)
    bg = (12, 14, 22)
    surface = (20, 26, 38)
    accent = (98, 148, 255)
    muted = (125, 135, 150)
    success = (40, 194, 154)
    warning = (235, 201, 109)
    danger = (230, 103, 103)
    fill_rect(screen, 0, 0, cols, rows, " ", muted, bg)
    fill_rect(screen, 0, 0, cols, 2, " ", bg, accent)
    draw_text(screen, 2, 0, "System monitor — Midnight theme", (255, 255, 255), accent, bold=True)
    draw_text(screen, cols - 32, 0, "cpu/mem gauges + process table", (230, 230, 230), accent)

    left_w = cols // 2 - 2
    draw_box(screen, 1, 3, left_w, rows - 6, muted, surface, "CPU / Memory")
    draw_text(screen, 4, 5, "CPU 72%", accent, surface, bold=True)
    draw_text(screen, 4, 6, "[###################-----]", success, surface, bold=True)
    draw_text(screen, 4, 8, "Memory 63%", accent, surface, bold=True)
    draw_text(screen, 4, 9, "[##################------]", warning, surface, bold=True)
    draw_text(screen, 4, 11, "Network throughput", muted, surface)
    draw_text(screen, 4, 12, "__/^^\\__/\\_/\\__/\\_/^^--__", accent, surface, bold=True)

    right_x = left_w + 2
    draw_box(screen, right_x, 3, cols - right_x - 2, rows - 6, muted, surface, "Processes")
    headers = "Process           CPU     Memory"
    draw_text(screen, right_x + 2, 5, headers, bg, accent, bold=True)
    rows_data = [
        ("zit-demo", "42.4%", "142 MB"),
        ("renderer", "37.2%", "120 MB"),
        ("metricsd", "18.6%", "94 MB"),
        ("net-tap", "12.1%", "88 MB"),
        ("backup", "7.4%", "73 MB"),
    ]
    for idx, row_data in enumerate(rows_data):
        y = 7 + idx * 2
        draw_text(screen, right_x + 2, y, f"{row_data[0]:<14} {row_data[1]:>6}   {row_data[2]:>7}", (230, 230, 230), surface)
        if idx == 1:
            fill_rect(screen, right_x + 1, y, cols - right_x - 4, 1, " ", bg, (20, 38, 68))
            draw_text(screen, right_x + 2, y, f"{row_data[0]:<14} {row_data[1]:>6}   {row_data[2]:>7}", (255, 255, 255), (20, 38, 68), bold=True)

    draw_text(screen, 2, rows - 2, "Theme: Midnight | q quit, p pause, t toggle themes | focus: renderer", bg, accent, bold=True)
    return screen


def make_mock_file_manager(rows: int, cols: int) -> TerminalEmulator:
    screen = TerminalEmulator(cols, rows)
    bg = (10, 12, 18)
    surface = (22, 24, 32)
    accent = (116, 207, 136)
    muted = (135, 140, 155)
    fill_rect(screen, 0, 0, cols, rows, " ", muted, bg)
    fill_rect(screen, 0, 0, cols, 1, " ", bg, accent)
    draw_text(screen, 2, 0, "File manager — tree + detail pane", (0, 0, 0), accent, bold=True)

    tree_w = cols // 3
    draw_box(screen, 1, 2, tree_w, rows - 4, muted, surface, "Workspace")
    tree_items = [
        ("▸ examples", False),
        ("  ▸ widget_examples", False),
        ("    ▶ system_monitor_example.zig", True),
        ("    ▶ file_manager_example.zig", False),
        ("    ▶ showcase_demo.zig", False),
        ("  ▸ realworld", False),
        ("    ▶ dashboard_demo.zig", False),
    ]
    for idx, (label, active) in enumerate(tree_items):
        y = 4 + idx
        color = accent if active else (230, 230, 230)
        bg_color = (24, 36, 28) if active else surface
        draw_text(screen, 3, y, label, color, bg_color, bold=active)

    right_x = tree_w + 3
    draw_box(screen, right_x, 2, cols - right_x - 2, rows - 8, muted, surface, "Details")
    header = "Name                       Kind        Size     Modified"
    draw_text(screen, right_x + 2, 4, header, (0, 0, 0), accent, bold=True)
    files = [
        ("src/", "dir", "-", "just now"),
        ("assets/", "dir", "-", "just now"),
        ("build.zig", "file", "9 KB", "1m ago"),
        ("README.md", "file", "24 KB", "5m ago"),
        ("zig-out/", "dir", "-", "9m ago"),
    ]
    for idx, row_data in enumerate(files):
        y = 6 + idx
        draw_text(screen, right_x + 2, y, f"{row_data[0]:<24} {row_data[1]:<10} {row_data[2]:>6}   {row_data[3]:>8}", (230, 230, 230), surface)
        if idx == 2:
            fill_rect(screen, right_x + 1, y, cols - right_x - 3, 1, " ", bg, (28, 40, 30))
            draw_text(screen, right_x + 2, y, f"{row_data[0]:<24} {row_data[1]:<10} {row_data[2]:>6}   {row_data[3]:>8}", (255, 255, 255), (28, 40, 30), bold=True)

    info_y = rows - 5
    draw_box(screen, 1, info_y, cols - 2, 3, muted, surface, "Status")
    draw_text(screen, 3, info_y + 1, "Navigation: arrows, enter to open, space for menu • Active theme: Forest", accent, surface, bold=True)
    draw_text(screen, 3, rows - 1, "Tip: use incremental search to jump between nodes", bg, accent, bold=True)
    return screen


def make_mock_showcase(rows: int, cols: int) -> TerminalEmulator:
    screen = TerminalEmulator(cols, rows)
    bg = (14, 14, 24)
    surface = (24, 26, 36)
    accent = (239, 155, 87)
    muted = (150, 154, 170)
    highlight = (90, 140, 255)
    fill_rect(screen, 0, 0, cols, rows, " ", muted, bg)
    fill_rect(screen, 0, 0, cols, 2, " ", bg, accent)
    draw_text(screen, 2, 0, "Showcase — mixed widgets", (0, 0, 0), accent, bold=True)

    card_w = (cols - 6) // 3
    titles = [("Notifications", highlight), ("Form wizard", accent), ("Progress dashboard", (116, 207, 136))]
    bodies = [
        [
            "[ toast ] Deploy complete",
            "[ banner ] New version available",
            "[ menu ] File  Edit  Help",
        ],
        [
            "Step 2/4: Billing",
            " - Country: █████     ",
            " - Card:    ████-4242 ",
            " - Save for later [x]",
        ],
        [
            "Gauge      [#####------] 62%",
            "Sparkline  ▁▂▃▂▅▆▅▃▂▂▃",
            "Table      ▶ Focus row 2/5",
        ],
    ]
    for idx, (title, color) in enumerate(titles):
        x = 2 + idx * (card_w + 1)
        draw_box(screen, x, 3, card_w, rows // 2, muted, surface, title)
        for line_idx, line in enumerate(bodies[idx]):
            draw_text(screen, x + 2, 5 + line_idx, line, color, surface, bold=True if line_idx == 0 else False)

    drawer_y = rows // 2 + 4
    draw_box(screen, 2, drawer_y, cols - 4, rows - drawer_y - 3, muted, surface, "Timeline + keyboard shortcuts")
    draw_text(screen, 4, drawer_y + 2, "⏺ Recorded events: resize • click • keypress • focus", highlight, surface, bold=True)
    draw_text(screen, 4, drawer_y + 4, "Shortcuts: [ctrl+p] palette  [t] theme  [q] quit  [f] focus next", (230, 230, 230), surface)
    draw_text(screen, 4, rows - 2, "Layouts snap to grids; widgets reuse Zit theme tokens for consistent styling.", (0, 0, 0), accent, bold=True)
    return screen


def set_winsize(fd: int, rows: int, cols: int) -> None:
    fcntl_payload = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, fcntl_payload)


def run_capture(cmd: List[str], rows: int, cols: int, duration: float) -> bytes:
    master_fd, slave_fd = pty.openpty()
    set_winsize(master_fd, rows, cols)
    env = os.environ.copy()
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    proc = subprocess.Popen(
        cmd,
        stdin=slave_fd,
        stdout=slave_fd,
        stderr=slave_fd,
        env=env,
        start_new_session=True,
    )
    os.close(slave_fd)

    buffer = bytearray()
    end_time = time.time() + duration
    try:
        while time.time() < end_time and proc.poll() is None:
            r, _, _ = select.select([master_fd], [], [], 0.05)
            if master_fd in r:
                chunk = os.read(master_fd, 4096)
                if not chunk:
                    break
                buffer.extend(chunk)
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            time.sleep(0.1)
        try:
            while True:
                chunk = os.read(master_fd, 4096)
                if not chunk:
                    break
                buffer.extend(chunk)
        except OSError:
            pass
        os.close(master_fd)
    return bytes(buffer)


def rgb_hex(color: Tuple[int, int, int]) -> str:
    return "#{:02x}{:02x}{:02x}".format(*color)


def render_svg(screen: TerminalEmulator, cell_w: int = 9, cell_h: int = 16, padding: int = 10) -> str:
    width = padding * 2 + screen.cols * cell_w
    height = padding * 2 + screen.rows * cell_h
    bg0 = screen.cells[0][0].bg if screen.cells else (0, 0, 0)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        f'  <rect x="0" y="0" width="{width}" height="{height}" fill="{rgb_hex(bg0)}" rx="8" ry="8"/>',
    ]

    # Draw background spans for non-default backgrounds.
    for y, row in enumerate(screen.cells):
        x = 0
        while x < screen.cols:
            start = x
            bg = row[x].bg
            while x < screen.cols and row[x].bg == bg:
                x += 1
            if bg != bg0:
                rect_x = padding + start * cell_w
                rect_w = (x - start) * cell_w
                rect_y = padding + y * cell_h
                lines.append(
                    f'  <rect x="{rect_x}" y="{rect_y}" width="{rect_w}" height="{cell_h}" fill="{rgb_hex(bg)}"/>'
                )

    font = "JetBrains Mono, 'Fira Code', SFMono-Regular, Consolas, Menlo, monospace"
    for y, row in enumerate(screen.cells):
        text_y = padding + y * cell_h
        lines.append(
            f'  <text x="{padding}" y="{text_y}" xml:space="preserve" font-family="{font}" font-size="13" '
            f'dominant-baseline="hanging">'
        )
        current_fg: Optional[Tuple[int, int, int]] = None
        current_bold = False
        buffer = ""

        def flush():
            nonlocal buffer, current_fg, current_bold
            if not buffer:
                return
            attrs = []
            if current_fg:
                attrs.append(f'fill="{rgb_hex(current_fg)}"')
            if current_bold:
                attrs.append('font-weight="700"')
            attr_str = " " + " ".join(attrs) if attrs else ""
            lines.append(f"    <tspan{attr_str}>{html.escape(buffer)}</tspan>")
            buffer = ""

        for cell in row:
            fg = cell.fg
            bold = cell.bold
            ch = cell.ch if cell.ch != "\x00" else " "
            if (fg != current_fg) or (bold != current_bold):
                flush()
                current_fg = fg
                current_bold = bold
            buffer += ch
        flush()
        lines.append("  </text>")
    lines.append("</svg>")
    return "\n".join(lines) + "\n"


def capture_to_svg(name: str, cmd: List[str], out_dir: Path, rows: int, cols: int, duration: float) -> Path:
    print(f"[capture] {name}: running {' '.join(cmd)}")
    data = run_capture(cmd, rows, cols, duration)
    screen = TerminalEmulator(cols, rows)
    screen.feed(data)
    out_path = out_dir / f"{name}.svg"
    out_path.write_text(render_svg(screen), encoding="utf-8")
    return out_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate SVG screenshots for Zit demos without external recorders.")
    parser.add_argument("--rows", type=int, default=28, help="Terminal rows")
    parser.add_argument("--cols", type=int, default=110, help="Terminal columns")
    parser.add_argument("--duration", type=float, default=3.0, help="Seconds to capture before terminating")
    parser.add_argument("--out", type=Path, default=Path("assets"), help="Output directory for SVGs")
    parser.add_argument("--bin-dir", type=Path, default=Path("zig-out/bin"), help="Directory containing compiled demos")
    parser.add_argument("--mock", action="store_true", help="Generate stylized mock screens without running demos (useful when PTYs are unavailable).")
    args = parser.parse_args()

    out_dir = args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.mock:
        mocks = {
            "system_monitor_example": make_mock_system_monitor,
            "file_manager_example": make_mock_file_manager,
            "showcase_demo": make_mock_showcase,
        }
        for name, builder in mocks.items():
            print(f"[mock] {name}: drawing stylized screen")
            screen = builder(args.rows, args.cols)
            out_path = out_dir / f"{name}.svg"
            out_path.write_text(render_svg(screen), encoding="utf-8")
            print(f"[mock] wrote {out_path}")
    else:
        demos = {
            "system_monitor_example": args.bin_dir / "system_monitor",
            "file_manager_example": args.bin_dir / "file_manager",
            "showcase_demo": args.bin_dir / "showcase_demo",
        }
        for name, path in demos.items():
            if not path.exists():
                raise SystemExit(f"missing demo binary: {path}. Run `zig build` first.")
            capture_to_svg(name, [str(path)], out_dir, args.rows, args.cols, args.duration)

    print(f"Screenshots saved to {out_dir}")


if __name__ == "__main__":
    main()
