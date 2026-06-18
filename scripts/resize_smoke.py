#!/usr/bin/env python3
"""Verify that a real PTY resize reaches Zit input handling.

The normal interactive smoke proves examples render and quit. This probe changes
the pseudo-terminal window size while `input_test` is running and requires the
example to print the new resize dimensions before it can pass.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

from interactive_example_smoke import (
    FATAL_OUTPUT_MARKERS,
    DEFAULT_EXAMPLES,
    Example,
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


DEFAULT_RESIZE_EXAMPLES = (
    "htop_clone",
    "file_manager",
    "text_editor",
    "dashboard_demo",
    "widget_gallery",
    "widget_gallery_extended",
    "widget_gallery_layouts",
)


def wait_for_text(master_fd: int, pid: int, output: bytearray, marker: str, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        output.extend(read_available(master_fd, 0.05))
        if marker in stripped_text(bytes(output)):
            return True
        if wait_for_pid(pid, 0.0) is not None:
            return False
    return False


def quit_child(master_fd: int, pid: int, timeout: float) -> int | None:
    deadline = time.monotonic() + timeout
    exit_code: int | None = None
    while time.monotonic() < deadline:
        try:
            os.write(master_fd, b"q")
        except OSError:
            exit_code = wait_for_pid(pid, 0.5)
            break
        exit_code = wait_for_pid(pid, 0.15)
        if exit_code is not None:
            break
    if exit_code is None:
        exit_code = wait_for_pid(pid, 0.0)
    return exit_code


def run_probe(root: Path, rows: int, cols: int, new_rows: int, new_cols: int, timeout: float, quit_timeout: float) -> bytes:
    if pty is None:
        print("resize smoke skipped: pty module is unavailable on this platform")
        return b""

    binary = binary_path(root, "input_test")
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

    output = bytearray()
    try:
        set_window_size(master_fd, rows, cols)

        if not wait_for_text(master_fd, pid, output, "Input Handler Test", timeout):
            terminate(pid)
            raise RuntimeError(
                f"input_test did not render before resize within {timeout:.1f}s\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )

        set_window_size(master_fd, new_rows, new_cols)
        marker = f"Resize: {new_cols}x{new_rows}"
        if not wait_for_text(master_fd, pid, output, marker, timeout):
            terminate(pid)
            raise RuntimeError(
                f"input_test did not report PTY resize marker {marker!r} within {timeout:.1f}s\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )

        exit_code = quit_child(master_fd, pid, quit_timeout)
        output.extend(read_available(master_fd, 0.2))
        if exit_code is None:
            terminate(pid)
            raise RuntimeError(
                f"input_test reported resize but did not exit after q within {quit_timeout:.1f}s\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )
        if exit_code != 0:
            raise RuntimeError(
                f"input_test exited with code {exit_code}\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )

        text = stripped_text(bytes(output))
        for marker_text in FATAL_OUTPUT_MARKERS:
            if marker_text in text:
                raise RuntimeError(
                    f"input_test emitted fatal diagnostic marker {marker_text!r}\n"
                    f"--- terminal tail ---\n{tail_text(bytes(output))}"
                )

        return bytes(output)
    finally:
        terminate(pid)
        try:
            os.close(master_fd)
        except OSError:
            pass


def run_example_resize_probe(
    root: Path,
    example: Example,
    rows: int,
    cols: int,
    new_rows: int,
    new_cols: int,
    timeout: float,
    quit_timeout: float,
) -> bytes:
    if pty is None:
        print("resize smoke skipped: pty module is unavailable on this platform")
        return b""

    binary = binary_path(root, example.binary)
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

    output = bytearray()
    try:
        set_window_size(master_fd, rows, cols)

        for marker in example.markers:
            if not wait_for_text(master_fd, pid, output, marker, timeout):
                terminate(pid)
                raise RuntimeError(
                    f"{example.binary} did not render marker {marker!r} before resize within {timeout:.1f}s\n"
                    f"--- terminal tail ---\n{tail_text(bytes(output))}"
                )

        initial_marker = f"resize: {cols}x{rows}"
        if not wait_for_text(master_fd, pid, output, initial_marker, timeout):
            terminate(pid)
            raise RuntimeError(
                f"{example.binary} did not report initial terminal size marker {initial_marker!r}\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )

        set_window_size(master_fd, new_rows, new_cols)
        resized_marker = f"resize: {new_cols}x{new_rows}"
        if not wait_for_text(master_fd, pid, output, resized_marker, timeout):
            terminate(pid)
            raise RuntimeError(
                f"{example.binary} did not redraw resize marker {resized_marker!r} within {timeout:.1f}s\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )

        exit_code = quit_child(master_fd, pid, quit_timeout)
        output.extend(read_available(master_fd, 0.2))
        if exit_code is None:
            terminate(pid)
            raise RuntimeError(
                f"{example.binary} redrew after resize but did not exit after q within {quit_timeout:.1f}s\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )
        if exit_code != 0:
            raise RuntimeError(
                f"{example.binary} exited with code {exit_code}\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )

        text = stripped_text(bytes(output))
        for marker_text in FATAL_OUTPUT_MARKERS:
            if marker_text in text:
                raise RuntimeError(
                    f"{example.binary} emitted fatal diagnostic marker {marker_text!r}\n"
                    f"--- terminal tail ---\n{tail_text(bytes(output))}"
                )

        return bytes(output)
    finally:
        terminate(pid)
        try:
            os.close(master_fd)
        except OSError:
            pass


def select_resize_examples(names: list[str] | None) -> list[Example]:
    by_name = {example.binary: example for example in DEFAULT_EXAMPLES}
    selected_names = names or list(DEFAULT_RESIZE_EXAMPLES)
    selected: list[Example] = []
    missing: list[str] = []
    for name in selected_names:
        if name in by_name:
            selected.append(by_name[name])
        else:
            missing.append(name)
    if missing:
        known = ", ".join(sorted(by_name))
        raise RuntimeError(f"unknown resize example(s): {', '.join(missing)}\nknown examples: {known}")
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-build", action="store_true", help="reuse zig-out/bin instead of running zig build first")
    parser.add_argument("--rows", type=int, default=40, help="initial PTY row count")
    parser.add_argument("--cols", type=int, default=120, help="initial PTY column count")
    parser.add_argument("--new-rows", type=int, default=31, help="resized PTY row count")
    parser.add_argument("--new-cols", type=int, default=91, help="resized PTY column count")
    parser.add_argument("--timeout", type=float, default=5.0, help="seconds to wait for render and resize markers")
    parser.add_argument("--quit-timeout", type=float, default=3.0, help="seconds to wait for q to terminate")
    parser.add_argument("--example", action="append", dest="examples", help="resizable example binary to probe; may be repeated")
    args = parser.parse_args()

    root = repo_root()
    if not args.no_build:
        ensure_binaries(root)

    data = run_probe(root, args.rows, args.cols, args.new_rows, args.new_cols, args.timeout, args.quit_timeout)
    if pty is not None:
        print(f"ok resize smoke: input_test reported {args.new_cols}x{args.new_rows} and quit ({len(data)} bytes)")

    examples = select_resize_examples(args.examples)
    for example in examples:
        example_data = run_example_resize_probe(root, example, args.rows, args.cols, args.new_rows, args.new_cols, args.timeout, args.quit_timeout)
        if pty is not None:
            print(f"ok resize smoke: {example.binary} redrew at {args.new_cols}x{args.new_rows} and quit ({len(example_data)} bytes)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        sys.stderr.write(f"error: {err}\n")
        raise SystemExit(1)
