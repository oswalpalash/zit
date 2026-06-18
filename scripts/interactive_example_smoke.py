#!/usr/bin/env python3
"""Launch interactive examples in a PTY, verify visible output, then quit.

This checks the contract that public TUI examples render in a real terminal and
exit on ``q``. Snapshot tests prove deterministic frames; this script proves the
interactive path.
"""

from __future__ import annotations

import argparse
import os
import re
import select
import signal
import struct
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

try:
    import fcntl
    import pty
    import termios
except ImportError:  # pragma: no cover - Windows CI skips this script.
    fcntl = None
    pty = None
    termios = None


ANSI_RE = re.compile(
    rb"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))"
)
FATAL_OUTPUT_MARKERS = (
    "error(DebugAllocator)",
    "memory leak",
    "thread panic",
    "panic:",
)


@dataclass(frozen=True)
class Example:
    binary: str
    markers: tuple[str, ...]


DEFAULT_EXAMPLES = (
    Example("terminal_test", ("Terminal size:", "Raw mode enabled")),
    Example("input_test", ("Input Handler Test", "Press keys")),
    Example("render_test", ("Zit Rendering Test", "Standard Colors")),
    Example("layout_test", ("Zit Layout Test", "Press 'q' to quit")),
    Example("demo", ("Zit TUI Library", "Click Me")),
    Example("widget_test", ("Widget Test", "Show Modal")),
    Example("hello_world", ("Hello world: press q to quit", "Hello, Zit!")),
    Example("button", ("Zit Button Widget Demo", "Basic Buttons")),
    Example("dashboard", ("Systems", "Usage")),
    Example("notifications", ("Notifications demo", "q = quit")),
    Example("table_widget", ("Table demo", "q quits")),
    Example("file_browser", ("File browser", "q quits")),
    Example("file_manager_example", ("Tab switches focus", "dashboard.zig")),
    Example("form_wizard", ("Fill the fields", "q quits")),
    Example("system_monitor", ("Theme:", "q quit")),
    Example("widget_showcase", ("Keys: q quit", "Theme:")),
    Example("htop_clone", ("htop-clone", "q quit")),
    Example("file_manager", ("file manager", "F10 quit")),
    Example("text_editor", ("main.zig", "Command Palette")),
    Example("dashboard_demo", ("dashboard", "status: green")),
    Example("widget_gallery", ("Table", "quality: visual")),
    Example("widget_gallery_extended", ("Telemetry", "Drawing Primitives")),
    Example("widget_gallery_layouts", ("Left pane", "Right pane")),
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def binary_path(root: Path, binary: str) -> Path:
    suffix = ".exe" if os.name == "nt" else ""
    return root / "zig-out" / "bin" / f"{binary}{suffix}"


def stripped_text(data: bytes) -> str:
    without_ansi = ANSI_RE.sub(b"", data)
    text = without_ansi.decode("utf-8", errors="replace")
    return text.replace("\r", "\n")


def tail_text(data: bytes, limit: int = 2400) -> str:
    text = stripped_text(data)
    return text[-limit:]


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


def set_window_size(fd: int, rows: int, cols: int) -> None:
    if fcntl is None or termios is None:
        return
    packed = struct.pack("HHHH", rows, cols, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, packed)


def read_available(master_fd: int, timeout: float) -> bytes:
    chunks: list[bytes] = []
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        ready, _, _ = select.select([master_fd], [], [], min(remaining, 0.05))
        if not ready:
            continue
        try:
            chunk = os.read(master_fd, 8192)
        except OSError:
            break
        if not chunk:
            break
        chunks.append(chunk)
    return b"".join(chunks)


def wait_for_pid(pid: int, timeout: float) -> int | None:
    def poll_once() -> int | None:
        try:
            waited_pid, status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return 0
        if waited_pid == pid:
            if os.WIFEXITED(status):
                return os.WEXITSTATUS(status)
            if os.WIFSIGNALED(status):
                return 128 + os.WTERMSIG(status)
            return 1
        return None

    if timeout <= 0:
        return poll_once()

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        code = poll_once()
        if code is not None:
            return code
        time.sleep(0.02)
    return None


def terminate(pid: int) -> None:
    if wait_for_pid(pid, 0.0) is not None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    if wait_for_pid(pid, 0.5) is None:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        _ = wait_for_pid(pid, 0.5)


def run_example(root: Path, example: Example, render_timeout: float, quit_timeout: float, rows: int, cols: int) -> bytes:
    if pty is None:
        raise RuntimeError("PTY support is unavailable on this platform")

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

    set_window_size(master_fd, rows, cols)

    output = bytearray()
    marker_seen = False
    deadline = time.monotonic() + render_timeout
    try:
        while time.monotonic() < deadline:
            output.extend(read_available(master_fd, 0.05))
            text = stripped_text(bytes(output))
            if all(marker in text for marker in example.markers):
                marker_seen = True
                break
            if wait_for_pid(pid, 0.0) is not None:
                break

        if not marker_seen:
            terminate(pid)
            output.extend(read_available(master_fd, 0.2))
            raise RuntimeError(
                f"{example.binary} did not render markers {example.markers!r} within {render_timeout:.1f}s\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )

        exit_code = None
        quit_deadline = time.monotonic() + quit_timeout
        while time.monotonic() < quit_deadline:
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
                f"{example.binary} rendered but did not exit after q within {quit_timeout:.1f}s\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )
        if exit_code != 0:
            raise RuntimeError(
                f"{example.binary} exited with code {exit_code}\n"
                f"--- terminal tail ---\n{tail_text(bytes(output))}"
            )
        text = stripped_text(bytes(output))
        for marker in FATAL_OUTPUT_MARKERS:
            if marker in text:
                raise RuntimeError(
                    f"{example.binary} emitted fatal diagnostic marker {marker!r}\n"
                    f"--- terminal tail ---\n{tail_text(bytes(output))}"
                )
        return bytes(output)
    finally:
        terminate(pid)
        try:
            os.close(master_fd)
        except OSError:
            pass


def select_examples(names: list[str] | None) -> list[Example]:
    examples = list(DEFAULT_EXAMPLES)
    if not names:
        return examples
    by_name = {example.binary: example for example in examples}
    selected: list[Example] = []
    missing: list[str] = []
    for name in names:
        if name in by_name:
            selected.append(by_name[name])
        else:
            missing.append(name)
    if missing:
        known = ", ".join(sorted(by_name))
        raise RuntimeError(f"unknown example(s): {', '.join(missing)}\nknown examples: {known}")
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", action="append", dest="targets", help="binary name to smoke; may be repeated")
    parser.add_argument("--no-build", action="store_true", help="reuse zig-out/bin instead of running zig build first")
    parser.add_argument("--render-timeout", type=float, default=5.0, help="seconds to wait for required markers")
    parser.add_argument("--quit-timeout", type=float, default=3.0, help="seconds to wait for q to terminate")
    parser.add_argument("--rows", type=int, default=40, help="PTY row count")
    parser.add_argument("--cols", type=int, default=120, help="PTY column count")
    args = parser.parse_args()

    if pty is None:
        print("interactive PTY smoke skipped: pty module is unavailable on this platform")
        return 0

    root = repo_root()
    examples = select_examples(args.targets)
    if not args.no_build:
        ensure_binaries(root)

    for example in examples:
        data = run_example(root, example, args.render_timeout, args.quit_timeout, args.rows, args.cols)
        print(f"ok {example.binary}: rendered markers and quit on q ({len(data)} bytes)")

    print(f"interactive PTY smoke passed for {len(examples)} example(s)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        sys.stderr.write(f"error: {err}\n")
        raise SystemExit(1)
