#!/usr/bin/env python3
"""Require public examples to restore terminal state they enable."""

from __future__ import annotations

import sys
from pathlib import Path
import re


PAIRS = (
    ("enterAlternateScreen", "exitAlternateScreen"),
    ("enableRawMode", "disableRawMode"),
    ("enableMouse", "disableMouse"),
    ("enableFocus", "disableFocus"),
    ("hideCursor", "showCursor"),
)

SILENT_CLEANUP_PATTERNS = (
    re.compile(r"\b(?:term|terminal)\.deinit\(\)\s+catch\s+\{\s*\}"),
    re.compile(r"\.(?:exitAlternateScreen|disableRawMode|showCursor)\(\)\s+catch\s+\{\s*\}"),
    re.compile(r"\binput_handler\.(?:disableMouse|disableFocus)\(\)\s+catch\s+\{\s*\}"),
)

PUBLIC_SNIPPET_PATHS = (
    Path("README.md"),
    Path("docs/API.md"),
    Path("docs/APP_LOOP_TUTORIAL.md"),
    Path("src/terminal/terminal.zig"),
)

MODE_SETUP_CONTRACTS = (
    ("enableMouseEvents", "self.is_mouse_enabled = true", "compat.fileWriteAll"),
    ("enableFocusEvents", "self.is_focus_reporting_enabled = true", "compat.fileWriteAll"),
    ("beginSynchronizedOutput", "self.is_sync_output = true", "compat.fileWriteAll"),
    ("enableBracketedPaste", "self.is_bracketed_paste = true", "compat.fileWriteAll"),
    ("enterAlternateScreen", "self.is_alt_screen = true", "compat.fileWriteAll"),
    ("hideCursor", "self.is_cursor_visible = false", "compat.fileWriteAll"),
    ("enableKittyKeyboardProtocol", "self.is_kitty_keyboard_enabled = true", "compat.fileWriteAll"),
)

INPUT_PROTOCOL_SETUP_FUNCTIONS = (
    "enableMouseEvents",
    "enableFocusEvents",
    "enableBracketedPaste",
    "enableKittyKeyboardProtocol",
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def iter_example_sources(root: Path) -> list[Path]:
    return sorted((root / "examples").rglob("*.zig"))


def iter_silent_cleanup_sources(root: Path) -> list[Path]:
    paths = [path for path in iter_example_sources(root) if "benchmarks" not in path.parts]
    paths.extend(root / rel for rel in PUBLIC_SNIPPET_PATHS)
    return sorted(set(paths))


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def validate_no_silent_cleanup(root: Path) -> list[str]:
    failures: list[str] = []
    for path in iter_silent_cleanup_sources(root):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(root)
        for pattern in SILENT_CLEANUP_PATTERNS:
            for match in pattern.finditer(text):
                failures.append(f"{rel}:{line_number(text, match.start())}: terminal cleanup errors must be reported, not swallowed with `catch {{}}`")
    return failures


def function_body(text: str, name: str) -> str | None:
    signature = f"pub fn {name}("
    start = text.find(signature)
    if start < 0:
        return None
    brace = text.find("{", start)
    if brace < 0:
        return None

    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:index]
    return None


def validate_terminal_driver_ownership(root: Path) -> list[str]:
    failures: list[str] = []
    terminal_text = (root / "src/terminal/terminal.zig").read_text(encoding="utf-8")
    input_text = (root / "src/input/input.zig").read_text(encoding="utf-8")

    if "compat.stdoutWriteAll" in terminal_text:
        failures.append("src/terminal/terminal.zig: terminal output must use the instance stdout_fd")

    for name, state_marker, write_marker in MODE_SETUP_CONTRACTS:
        body = function_body(terminal_text, name)
        if body is None:
            failures.append(f"src/terminal/terminal.zig: missing mode setup function {name}")
            continue
        state_index = body.find(state_marker)
        write_index = body.find(write_marker)
        if state_index < 0 or write_index < 0 or state_index > write_index:
            failures.append(
                f"src/terminal/terminal.zig: {name} must record its cleanup obligation before the fallible terminal write"
            )

    for name in INPUT_PROTOCOL_SETUP_FUNCTIONS:
        body = function_body(terminal_text, name)
        if body is None or "self.supportsVtInputProtocols()" not in body:
            failures.append(
                f"src/terminal/terminal.zig: {name} must require negotiated Windows VT input and output"
            )

    deinit_body = function_body(terminal_text, "deinit")
    if deinit_body is None:
        failures.append("src/terminal/terminal.zig: missing Terminal.deinit")
    else:
        raw_index = deinit_body.find("self.disableRawMode()")
        for cleanup in (
            "showCursor",
            "disableMouseEvents",
            "disableFocusEvents",
            "endSynchronizedOutput",
            "disableBracketedPaste",
            "exitAlternateScreen",
        ):
            cleanup_index = deinit_body.find(f"self.{cleanup}()")
            if raw_index < 0 or cleanup_index < 0 or cleanup_index > raw_index:
                failures.append(
                    f"src/terminal/terminal.zig: deinit must run {cleanup} before disableRawMode so Windows VT output remains available"
                )
        if "self.restoreWindowsOutputModeIfNeeded(&first_error)" not in deinit_body:
            failures.append("src/terminal/terminal.zig: deinit must restore VT output enabled during Windows initialization")

    raw_mode_body = function_body(terminal_text, "enableRawMode")
    if raw_mode_body is None:
        failures.append("src/terminal/terminal.zig: missing enableRawMode")
    else:
        for marker in ("self.windows_vt_input_enabled = true", "self.windows_vt_input_enabled = false"):
            if marker not in raw_mode_body:
                failures.append(f"src/terminal/terminal.zig: enableRawMode missing Windows lifecycle marker {marker}")

        input_setup_index = raw_mode_body.find("const vt_input_mode")
        raw_obligation_index = raw_mode_body.find("self.is_raw_mode = true;", input_setup_index)
        output_setup_index = raw_mode_body.find("const base_out_mode")
        if input_setup_index < 0 or raw_obligation_index < 0 or output_setup_index < 0 or raw_obligation_index > output_setup_index:
            failures.append(
                "src/terminal/terminal.zig: enableRawMode must record raw-input cleanup before Windows output setup"
            )

        rollback_index = raw_mode_body.find(
            "windows_console.SetConsoleMode(self.stdin_fd, info.in_mode).toBool()",
            output_setup_index,
        )
        rollback_clear_index = raw_mode_body.find("self.is_raw_mode = false;", rollback_index)
        rollback_retry_index = raw_mode_body.find("self.is_raw_mode = true;", rollback_clear_index + 1)
        rollback_return_index = raw_mode_body.find("return error.SetConsoleModeFailure;", rollback_index)
        if (
            rollback_index < 0
            or rollback_clear_index < 0
            or rollback_retry_index < 0
            or rollback_return_index < 0
            or rollback_clear_index > rollback_return_index
            or rollback_retry_index > rollback_return_index
        ):
            failures.append(
                "src/terminal/terminal.zig: failed Windows output setup must clear the obligation only after input restore and retain it when restore fails"
            )

    if "mouse_enabled:" in input_text:
        failures.append("src/input/input.zig: InputHandler must not duplicate terminal mouse protocol state")
    if "focus_reporting_enabled:" in input_text:
        failures.append("src/input/input.zig: InputHandler must not duplicate terminal focus protocol state")
    enable_body = function_body(input_text, "enableMouse")
    disable_body = function_body(input_text, "disableMouse")
    if enable_body is not None and "?1000h" in enable_body:
        failures.append("src/input/input.zig: InputHandler.enableMouse must not duplicate terminal mouse escape sequences")
    if disable_body is not None and "?1000l" in disable_body:
        failures.append("src/input/input.zig: InputHandler.disableMouse must not duplicate terminal mouse escape sequences")
    if enable_body is None or "self.term.enableMouseEvents()" not in enable_body:
        failures.append("src/input/input.zig: InputHandler.enableMouse must delegate to Terminal.enableMouseEvents")
    if disable_body is None or "self.term.disableMouseEvents()" not in disable_body:
        failures.append("src/input/input.zig: InputHandler.disableMouse must delegate to Terminal.disableMouseEvents")

    enable_focus_body = function_body(input_text, "enableFocus")
    disable_focus_body = function_body(input_text, "disableFocus")
    if enable_focus_body is None or "self.term.enableFocusEvents()" not in enable_focus_body:
        failures.append("src/input/input.zig: InputHandler.enableFocus must delegate to Terminal.enableFocusEvents")
    if disable_focus_body is None or "self.term.disableFocusEvents()" not in disable_focus_body:
        failures.append("src/input/input.zig: InputHandler.disableFocus must delegate to Terminal.disableFocusEvents")

    return failures


def validate_fragmented_input_contract(root: Path) -> list[str]:
    failures: list[str] = []
    input_text = (root / "src/input/input.zig").read_text(encoding="utf-8")
    smoke_text = (root / "scripts/interactive_example_smoke.py").read_text(encoding="utf-8")

    for marker in (
        "default_sequence_timeout_ms",
        "PosixTimedByteReader",
        "WindowsTimedByteReader",
        "setSequenceTimeout",
        'test "Windows input wait distinguishes timeout and readiness"',
        'test "input handler reads configured terminal stdin handle"',
    ):
        if marker not in input_text:
            failures.append(f"src/input/input.zig: missing fragmented-input contract marker {marker}")

    if "parseEscapeSequenceMac" in input_text or "parseEscapeSequenceStandard" in input_text:
        failures.append("src/input/input.zig: escape parsing must use the shared timed continuation path")

    read_event_body = function_body(input_text, "readEvent")
    if read_event_body is None:
        failures.append("src/input/input.zig: missing InputHandler.readEvent")
    else:
        if "std.Io.File.stdin()" in read_event_body:
            failures.append("src/input/input.zig: InputHandler.readEvent must read the Terminal instance stdin handle")
        if ".handle = self.term.stdin_fd" not in read_event_body:
            failures.append("src/input/input.zig: InputHandler.readEvent missing terminal-owned stdin file")
        if "WindowsTimedByteReader" not in read_event_body:
            failures.append("src/input/input.zig: Windows escape and UTF-8 continuations must use the configured timeout")

    for marker in (
        "interaction_byte_delay",
        "interaction_byte_delay=0.002",
    ):
        if marker not in smoke_text:
            failures.append(f"scripts/interactive_example_smoke.py: missing fragmented PTY input marker {marker}")

    return failures


def main() -> int:
    root = repo_root()
    failures: list[str] = []
    checked = 0

    for path in iter_example_sources(root):
        if "benchmarks" in path.parts:
            continue

        text = path.read_text(encoding="utf-8")
        if "initInteractive(" not in text:
            continue

        checked += 1
        rel = path.relative_to(root)
        for setup, cleanup in PAIRS:
            setup_call = f".{setup}("
            cleanup_call = f".{cleanup}("
            setup_index = text.find(setup_call)
            cleanup_index = text.find(cleanup_call)
            setup_present = setup_index >= 0
            cleanup_present = cleanup_index >= 0
            if setup_present and not cleanup_present:
                failures.append(f"{rel}: calls {setup} without {cleanup}")
            if cleanup_present and not setup_present:
                failures.append(f"{rel}: calls {cleanup} without {setup}")
            if setup_present and cleanup_present:
                if cleanup_index < setup_index:
                    failures.append(f"{rel}: calls {cleanup} before {setup}")
                elif "defer" not in text[setup_index:cleanup_index]:
                    failures.append(f"{rel}: restores {cleanup} without deferring it after {setup}")

    failures.extend(validate_no_silent_cleanup(root))
    failures.extend(validate_terminal_driver_ownership(root))
    failures.extend(validate_fragmented_input_contract(root))

    if failures:
        sys.stderr.write("interactive examples must restore terminal state they enable and report cleanup failures:\n")
        for failure in failures:
            sys.stderr.write(f"  - {failure}\n")
        return 1

    print(
        f"checked {checked} interactive example(s) for terminal-state cleanup symmetry, "
        "driver ownership, Windows VT negotiation, fragmented input, and silent cleanup catches"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
