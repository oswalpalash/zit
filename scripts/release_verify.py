#!/usr/bin/env python3
"""Run the full public release verification gate.

This is intentionally broader than ``zig build quality``. It compiles docs,
checks public build targets, runs cross-target smoke builds, exercises
interactive examples and resize handling under a PTY, and repeats deterministic
visual captures.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Command:
    label: str
    argv: tuple[str, ...]
    timeout: int = 300


SCRIPT_COMPILE_TARGETS = (
    "scripts/check_accessibility_metadata.py",
    "scripts/check_application_input_binding.py",
    "scripts/check_build_steps.py",
    "scripts/check_ci_script_coverage.py",
    "scripts/check_contribution_gates.py",
    "scripts/check_debug_allocator_cleanup.py",
    "scripts/check_docs_commands.py",
    "scripts/check_docs_links.py",
    "scripts/check_docs_zig_snippets.py",
    "scripts/check_example_coverage.py",
    "scripts/check_interactive_alt_screen.py",
    "scripts/check_mouse_coordinate_contract.py",
    "scripts/check_mouse_hit_coverage.py",
    "scripts/check_owned_allocation_patterns.py",
    "scripts/check_terminal_state_cleanup.py",
    "scripts/check_unreachable_catches.py",
    "scripts/check_widget_owner_casts.py",
    "scripts/check_widget_coverage.py",
    "scripts/interactive_example_smoke.py",
    "scripts/mouse_alignment_smoke.py",
    "scripts/release_verify.py",
    "scripts/resize_smoke.py",
    "scripts/visual_repeat_check.py",
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def run(root: Path, command: Command, env: dict[str, str]) -> None:
    print(f"==> {command.label}", flush=True)
    start = time.monotonic()
    try:
        proc = subprocess.run(
            command.argv,
            cwd=root,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=command.timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout if isinstance(exc.stdout, str) else (exc.stdout or b"").decode("utf-8", errors="replace")
        sys.stderr.write(output[-6000:])
        raise RuntimeError(f"{command.label} timed out after {command.timeout}s")

    elapsed = time.monotonic() - start
    if proc.stdout:
        sys.stdout.write(proc.stdout)
        if not proc.stdout.endswith("\n"):
            sys.stdout.write("\n")
    if proc.returncode != 0:
        raise RuntimeError(f"{command.label} failed with exit code {proc.returncode}")
    print(f"<== {command.label} ok elapsed={elapsed:.1f}s", flush=True)


def commands(args: argparse.Namespace, docs_dir: Path) -> list[Command]:
    out: list[Command] = [
        Command("format", ("zig", "fmt", "--check", "src/", "examples/", "build.zig"), 120),
        Command("python script compile", ("python3", "-m", "py_compile", *SCRIPT_COMPILE_TARGETS), 120),
        Command("quality", ("zig", "build", "quality"), 300),
        Command("smoke", ("zig", "build", "smoke"), 300),
        Command("test", ("zig", "build", "test"), 300),
        Command("bench", ("zig", "build", "bench"), 300),
        Command("docs", ("zig", "build-lib", "src/main.zig", f"-femit-docs={docs_dir}", "-fno-emit-bin"), 300),
        Command("linux cross smoke", ("zig", "build", "smoke", "-Dtarget=x86_64-linux"), 300),
        Command("windows cross smoke", ("zig", "build", "smoke", "-Dtarget=x86_64-windows"), 300),
        Command("public build steps", ("python3", "scripts/check_build_steps.py", "--skip", "release-check", "--timeout", str(args.step_timeout)), max(args.step_timeout * 35, 300)),
        Command("debug allocator cleanup", ("python3", "scripts/check_debug_allocator_cleanup.py"), 120),
        Command("docs commands", ("python3", "scripts/check_docs_commands.py"), 120),
        Command("docs links", ("python3", "scripts/check_docs_links.py"), 120),
        Command("docs Zig snippets", ("python3", "scripts/check_docs_zig_snippets.py"), 120),
        Command("CI script coverage", ("python3", "scripts/check_ci_script_coverage.py"), 120),
        Command("contribution gates", ("python3", "scripts/check_contribution_gates.py"), 120),
        Command("accessibility metadata", ("python3", "scripts/check_accessibility_metadata.py"), 120),
        Command("application input binding", ("python3", "scripts/check_application_input_binding.py"), 120),
        Command("example coverage", ("python3", "scripts/check_example_coverage.py"), 120),
        Command("interactive alternate screen", ("python3", "scripts/check_interactive_alt_screen.py"), 120),
        Command("mouse coordinate contract", ("python3", "scripts/check_mouse_coordinate_contract.py"), 120),
        Command("mouse hit coverage", ("python3", "scripts/check_mouse_hit_coverage.py"), 120),
        Command("owned allocation patterns", ("python3", "scripts/check_owned_allocation_patterns.py"), 120),
        Command("terminal state cleanup", ("python3", "scripts/check_terminal_state_cleanup.py"), 120),
        Command("unreachable catch patterns", ("python3", "scripts/check_unreachable_catches.py"), 120),
        Command("widget coverage", ("python3", "scripts/check_widget_coverage.py"), 120),
        Command("widget owner casts", ("python3", "scripts/check_widget_owner_casts.py"), 120),
        Command("interactive PTY smoke", ("python3", "scripts/interactive_example_smoke.py"), 300),
        Command("resize PTY smoke", ("python3", "scripts/resize_smoke.py", "--no-build"), 120),
        Command("mouse alignment PTY smoke", ("python3", "scripts/mouse_alignment_smoke.py", "--no-build"), 120),
    ]
    if not args.skip_visual:
        out.append(Command("visual repeat", ("python3", "scripts/visual_repeat_check.py", "--count", str(args.visual_count)), 300))
    return out


def verify_artifacts(root: Path, docs_dir: Path, skip_visual: bool) -> None:
    required_docs = (docs_dir / "index.html", docs_dir / "main.js", docs_dir / "main.wasm", docs_dir / "sources.tar")
    missing_docs = [path for path in required_docs if not path.exists()]
    if missing_docs:
        raise RuntimeError("docs generation missing artifact(s): " + ", ".join(str(path) for path in missing_docs))

    if skip_visual:
        return

    visual_dir = root / "zig-out" / "visual-repeat"
    required_visual = (visual_dir / "manifest.json", visual_dir / "contact-sheet.svg")
    missing_visual = [path for path in required_visual if not path.exists()]
    if missing_visual:
        raise RuntimeError("visual repeat missing artifact(s): " + ", ".join(str(path) for path in missing_visual))

    png = visual_dir / "contact-sheet.png"
    if png.exists():
        print(f"visual contact sheet: {png}")
    else:
        print(f"visual contact sheet: {visual_dir / 'contact-sheet.svg'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-visual", action="store_true", help="skip repeated visual captures")
    parser.add_argument("--visual-count", type=int, default=4, help="captures per visual target")
    parser.add_argument("--step-timeout", type=int, default=120, help="seconds per public build step")
    args = parser.parse_args()

    if args.visual_count < 2:
        parser.error("--visual-count must be at least 2")

    root = repo_root()
    docs_dir = root / "zig-out" / "docs-release"
    if docs_dir.exists():
        shutil.rmtree(docs_dir)
    docs_dir.parent.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")

    for command in commands(args, docs_dir):
        run(root, command, env)

    verify_artifacts(root, docs_dir, args.skip_visual)
    print("release verification passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        sys.stderr.write(f"error: {err}\n")
        raise SystemExit(1)
