#!/usr/bin/env python3
"""Run every non-destructive public `zig build` step with a timeout.

This catches build-step regressions that `zig build smoke` can miss, including
public run steps that accidentally require unavailable terminal state or hang.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path


STEP_RE = re.compile(r"^\s{2}([A-Za-z0-9_-]+)\s{2,}")
DEFAULT_SKIP = {"uninstall"}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def discover_steps(root: Path) -> list[str]:
    proc = subprocess.run(
        ["zig", "build", "--help"],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout)
        raise RuntimeError("`zig build --help` failed")

    steps: list[str] = []
    in_steps = False
    for line in proc.stdout.splitlines():
        if line == "Steps:":
            in_steps = True
            continue
        if in_steps and not line.startswith("  "):
            break
        if in_steps:
            match = STEP_RE.match(line)
            if match:
                steps.append(match.group(1))
    if not steps:
        raise RuntimeError("could not discover any `zig build` steps")
    return steps


def tail(text: str, max_chars: int = 4000) -> str:
    if len(text) <= max_chars:
        return text
    return text[-max_chars:]


def run_step(root: Path, step: str, timeout: int, env: dict[str, str]) -> tuple[bool, str, float]:
    start = time.monotonic()
    try:
        proc = subprocess.run(
            ["zig", "build", step],
            cwd=root,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout if isinstance(exc.stdout, str) else (exc.stdout or b"").decode("utf-8", errors="replace")
        return False, f"timeout after {timeout}s\n{tail(output)}", time.monotonic() - start

    output = proc.stdout or ""
    if proc.returncode != 0:
        return False, f"exit {proc.returncode}\n{tail(output)}", time.monotonic() - start
    return True, output, time.monotonic() - start


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=int, default=120, help="seconds allowed per build step")
    parser.add_argument("--skip", action="append", default=[], help="step to skip; may be repeated")
    parser.add_argument("--only", action="append", default=[], help="step to run; may be repeated")
    parser.add_argument("--quiet", action="store_true", help="only print failures and final status")
    args = parser.parse_args()

    root = repo_root()
    discovered = discover_steps(root)
    selected = args.only or discovered
    skip = DEFAULT_SKIP | set(args.skip)
    steps = [step for step in selected if step not in skip]

    missing = [step for step in selected if step not in discovered]
    if missing:
        sys.stderr.write(f"unknown build step(s): {', '.join(missing)}\n")
        return 2

    env = os.environ.copy()
    env.setdefault("TERM", "xterm-256color")
    env.setdefault("COLORTERM", "truecolor")

    failures: list[tuple[str, str]] = []
    for step in steps:
        if not args.quiet:
            print(f"==> zig build {step}", flush=True)
        ok, output, elapsed = run_step(root, step, args.timeout, env)
        if ok:
            if not args.quiet:
                lines = output.strip().splitlines()
                for line in lines[-3:]:
                    print(f"    {line}", flush=True)
                print(f"<== {step} ok elapsed={elapsed:.1f}s", flush=True)
        else:
            failures.append((step, output))
            print(f"<== {step} failed elapsed={elapsed:.1f}s", flush=True)

    if failures:
        print("\nFAILURES", flush=True)
        for step, output in failures:
            print(f"--- {step}\n{output}", flush=True)
        return 1

    print(f"\nchecked {len(steps)} public build step(s)", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
