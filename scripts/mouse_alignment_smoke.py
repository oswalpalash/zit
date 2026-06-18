#!/usr/bin/env python3
"""Verify PTY mouse coordinates align with rendered widget hit boxes.

This sends real SGR mouse sequences through a pseudo-terminal. It first proves
that terminal protocol coordinates are normalized to Zit's zero-based screen
coordinates, then clicks rendered demo controls above, on the border, and on
the content row. Above-target and border-row clicks must not fire; content
clicks must update visible status text.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

from interactive_example_smoke import (
    FATAL_OUTPUT_MARKERS,
    binary_path,
    ensure_binaries,
    pty,
    read_available,
    repo_root,
    set_window_size,
    stripped_text,
    tail_text,
    terminate,
    wait_for_pid,
)


def sgr_press(col: int, row: int, button: int = 0) -> bytes:
    return f"\x1b[<{button};{col};{row}M".encode("ascii")


def sgr_release(col: int, row: int, button: int = 0) -> bytes:
    return f"\x1b[<{button};{col};{row}m".encode("ascii")


def send_click(master_fd: int, col: int, row: int) -> None:
    os.write(master_fd, sgr_press(col, row))
    os.write(master_fd, sgr_release(col, row))


def assert_healthy(pid: int, output: bytearray, label: str) -> None:
    exit_code = wait_for_pid(pid, 0.0)
    if exit_code is not None:
        raise RuntimeError(
            f"{label} exited before the mouse probe completed with code {exit_code}\n"
            f"--- terminal tail ---\n{tail_text(bytes(output))}"
        )

    text = stripped_text(bytes(output))
    for marker in FATAL_OUTPUT_MARKERS:
        if marker in text:
            raise RuntimeError(
                f"{label} emitted fatal diagnostic marker {marker!r}\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )


def wait_for_text(master_fd: int, pid: int, output: bytearray, label: str, marker: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        output.extend(read_available(master_fd, 0.05))
        if marker in stripped_text(bytes(output)):
            return
        assert_healthy(pid, output, label)
    raise RuntimeError(
        f"{label} did not emit marker {marker!r} within {timeout:.1f}s\n"
        f"--- terminal tail ---\n{tail_text(bytes(output))}"
    )


def assert_absent_after(master_fd: int, pid: int, output: bytearray, label: str, forbidden: str, delay: float) -> None:
    deadline = time.monotonic() + delay
    while time.monotonic() < deadline:
        output.extend(read_available(master_fd, 0.05))
        assert_healthy(pid, output, label)

    if forbidden in stripped_text(bytes(output)):
        raise RuntimeError(
            f"{label} emitted forbidden marker {forbidden!r}\n"
            f"--- terminal tail ---\n{tail_text(bytes(output))}"
        )


def quit_child(master_fd: int, pid: int, output: bytearray, label: str, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    exit_code: int | None = None
    while time.monotonic() < deadline:
        try:
            os.write(master_fd, b"q")
        except OSError:
            exit_code = wait_for_pid(pid, 0.5)
            break
        exit_code = wait_for_pid(pid, 0.15)
        output.extend(read_available(master_fd, 0.02))
        if exit_code is not None:
            break

    if exit_code is None:
        exit_code = wait_for_pid(pid, 0.0)
    output.extend(read_available(master_fd, 0.2))
    if exit_code is None:
        terminate(pid)
        raise RuntimeError(
            f"{label} did not exit after q within {timeout:.1f}s\n"
            f"--- terminal tail ---\n{tail_text(bytes(output))}"
        )
    if exit_code != 0:
        raise RuntimeError(
            f"{label} exited with code {exit_code}\n"
            f"--- terminal tail ---\n{tail_text(bytes(output))}"
        )


def spawn(root: Path, binary_name: str, rows: int, cols: int) -> tuple[int, int]:
    binary = binary_path(root, binary_name)
    if not binary.exists():
        raise RuntimeError(f"missing binary: {binary}")

    pid, master_fd = pty.fork()
    if pid == 0:
        os.chdir(root)
        os.execvpe(str(binary), [str(binary)], {
            **os.environ,
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "COLUMNS": str(cols),
            "LINES": str(rows),
        })
        os._exit(127)

    set_window_size(master_fd, rows, cols)
    return pid, master_fd


def run_input_coordinate_probe(root: Path, timeout: float, quit_timeout: float) -> bytes:
    pid, master_fd = spawn(root, "input_test", 24, 80)
    output = bytearray()
    try:
        wait_for_text(master_fd, pid, output, "input_test", "Input Handler Test", timeout)
        send_click(master_fd, 1, 1)
        wait_for_text(master_fd, pid, output, "input_test", "Mouse: press at (0,0) button 1", timeout)
        quit_child(master_fd, pid, output, "input_test", quit_timeout)
        return bytes(output)
    finally:
        terminate(pid)
        try:
            os.close(master_fd)
        except OSError:
            pass


def run_demo_click_probe(root: Path, timeout: float, quit_timeout: float) -> bytes:
    pid, master_fd = spawn(root, "demo", 40, 120)
    output = bytearray()
    try:
        wait_for_text(master_fd, pid, output, "demo", "Click Me", timeout)

        # Demo button internal rect at 120x40: x=4..29, y=9..11.
        # SGR coordinates are one-based. The top border is terminal row 10;
        # only the visual content row at terminal row 11 should activate.
        send_click(master_fd, 18, 9)
        assert_absent_after(master_fd, pid, output, "demo", "Button clicked", 0.25)

        send_click(master_fd, 18, 10)
        assert_absent_after(master_fd, pid, output, "demo", "Button clicked", 0.25)

        send_click(master_fd, 18, 11)
        wait_for_text(master_fd, pid, output, "demo", "Button clicked", timeout)

        # Demo checkbox visual rect at 120x40: terminal row 14, columns 6..21.
        send_click(master_fd, 10, 13)
        assert_absent_after(master_fd, pid, output, "demo", "enabled", 0.25)
        send_click(master_fd, 10, 14)
        wait_for_text(master_fd, pid, output, "demo", "enabled", timeout)

        quit_child(master_fd, pid, output, "demo", quit_timeout)
        return bytes(output)
    finally:
        terminate(pid)
        try:
            os.close(master_fd)
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true", help="reuse zig-out/bin instead of running zig build first")
    parser.add_argument("--timeout", type=float, default=5.0, help="seconds to wait for render and click markers")
    parser.add_argument("--quit-timeout", type=float, default=3.0, help="seconds to wait for q to terminate")
    args = parser.parse_args()

    if pty is None:
        print("mouse alignment smoke skipped: pty module is unavailable on this platform")
        return 0

    root = repo_root()
    if not args.no_build:
        ensure_binaries(root)

    input_data = run_input_coordinate_probe(root, args.timeout, args.quit_timeout)
    print(f"ok mouse smoke: input_test normalized SGR 1x1 to 0x0 ({len(input_data)} bytes)")

    demo_data = run_demo_click_probe(root, args.timeout, args.quit_timeout)
    print(f"ok mouse smoke: demo rejected above/border clicks and accepted content clicks ({len(demo_data)} bytes)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        sys.stderr.write(f"error: {err}\n")
        raise SystemExit(1)
