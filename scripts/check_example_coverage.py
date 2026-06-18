#!/usr/bin/env python3
"""Keep public example verification manifests aligned with build targets.

The build file is the source of truth for public example binaries. This checker
prevents new examples from silently bypassing the PTY smoke tests, public
build-step classification, or repeated visual capture coverage.
"""

from __future__ import annotations

import ast
import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ExampleDecl:
    binary: str
    step: str
    path: str


ROOT = Path(__file__).resolve().parents[1]
BUILD_FILE = ROOT / "build.zig"
INTERACTIVE_SMOKE = ROOT / "scripts" / "interactive_example_smoke.py"
BUILD_STEP_CHECKER = ROOT / "scripts" / "check_build_steps.py"
VISUAL_REPEAT = ROOT / "scripts" / "visual_repeat_check.py"

ARRAY_EXAMPLE_RE = re.compile(
    r'\.\{ \.name = "(?P<binary>[^"]+)", \.description = "[^"]+", '
    r'\.path = "(?P<path>examples/[^"]+\.zig)", \.step_name = "(?P<step>[^"]+)" \}'
)
SINGLE_EXAMPLE_RE = re.compile(
    r'\.root_source_file = b\.path\("(?P<path>examples/[^"]+\.zig)"\),'
    r".*?const [A-Za-z0-9_]+ = b\.addExecutable\(\.\{\s*"
    r'\.name = "(?P<binary>[^"]+)".*?'
    r'const [A-Za-z0-9_]+_step = b\.step\("(?P<step>[^"]+)"',
    re.DOTALL,
)
SNAPSHOT_HELPERS = ('@import("interactive_snapshot.zig")', '@import("example_snapshot.zig")')
NON_EXAMPLE_INTERACTIVE_STEPS = {"resize-smoke", "mouse-smoke"}


def parse_build_examples() -> list[ExampleDecl]:
    text = BUILD_FILE.read_text(encoding="utf-8")
    examples: list[ExampleDecl] = []

    single_section = text.split("// Add widget examples", 1)[0]
    for match in SINGLE_EXAMPLE_RE.finditer(single_section):
        path = match.group("path")
        if "/benchmarks/" not in path:
            examples.append(ExampleDecl(match.group("binary"), match.group("step"), path))

    for match in ARRAY_EXAMPLE_RE.finditer(text):
        examples.append(ExampleDecl(match.group("binary"), match.group("step"), match.group("path")))

    if not examples:
        raise RuntimeError("could not discover public example declarations in build.zig")

    for field in ("binary", "step", "path"):
        values = [getattr(example, field) for example in examples]
        duplicates = sorted({value for value in values if values.count(value) > 1})
        if duplicates:
            raise RuntimeError(f"duplicate example {field}(s) in build.zig: {', '.join(duplicates)}")

    missing = [example.path for example in examples if not (ROOT / example.path).exists()]
    if missing:
        raise RuntimeError("build.zig references missing example file(s): " + ", ".join(sorted(missing)))

    return examples


def parse_assignment(path: Path, name: str) -> ast.AST:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == name:
                    return node.value
    raise RuntimeError(f"{path.relative_to(ROOT)}: missing assignment {name}")


def parse_interactive_binaries() -> set[str]:
    value = parse_assignment(INTERACTIVE_SMOKE, "DEFAULT_EXAMPLES")
    if not isinstance(value, (ast.Tuple, ast.List)):
        raise RuntimeError("scripts/interactive_example_smoke.py: DEFAULT_EXAMPLES must be a tuple or list")

    binaries: set[str] = set()
    for item in value.elts:
        if not isinstance(item, ast.Call) or not item.args:
            raise RuntimeError("scripts/interactive_example_smoke.py: DEFAULT_EXAMPLES contains a non-Example entry")
        first_arg = item.args[0]
        if not isinstance(first_arg, ast.Constant) or not isinstance(first_arg.value, str):
            raise RuntimeError("scripts/interactive_example_smoke.py: Example binary must be a string literal")
        binaries.add(first_arg.value)
    return binaries


def parse_literal_set(path: Path, name: str) -> set[str]:
    value = ast.literal_eval(parse_assignment(path, name))
    if not isinstance(value, (set, tuple, list)):
        raise RuntimeError(f"{path.relative_to(ROOT)}: {name} must be a literal sequence")
    return {str(item) for item in value}


def snapshot_capable(examples: list[ExampleDecl]) -> set[str]:
    out: set[str] = set()
    for example in examples:
        text = (ROOT / example.path).read_text(encoding="utf-8")
        if any(helper in text for helper in SNAPSHOT_HELPERS):
            out.add(example.binary)
    return out


def report_missing(label: str, missing: set[str], errors: list[str]) -> None:
    if missing:
        errors.append(f"{label} missing: {', '.join(sorted(missing))}")


def report_extra(label: str, extra: set[str], errors: list[str]) -> None:
    if extra:
        errors.append(f"{label} has stale/unknown entries: {', '.join(sorted(extra))}")


def main() -> int:
    try:
        examples = parse_build_examples()
        expected_binaries = {example.binary for example in examples}
        expected_steps = {example.step for example in examples}
        interactive_binaries = parse_interactive_binaries()
        interactive_steps = parse_literal_set(BUILD_STEP_CHECKER, "INTERACTIVE_STEPS")
        visual_targets = parse_literal_set(VISUAL_REPEAT, "DEFAULT_TARGETS")
    except RuntimeError as err:
        sys.stderr.write(f"error: {err}\n")
        return 1

    expected_visual_binaries = snapshot_capable(examples)
    visual_binaries = {target.replace("-", "_") for target in visual_targets}

    errors: list[str] = []
    report_missing("interactive smoke DEFAULT_EXAMPLES", expected_binaries - interactive_binaries, errors)
    report_extra("interactive smoke DEFAULT_EXAMPLES", interactive_binaries - expected_binaries, errors)
    report_missing("check_build_steps INTERACTIVE_STEPS", expected_steps - interactive_steps, errors)
    report_extra("check_build_steps INTERACTIVE_STEPS", interactive_steps - expected_steps - NON_EXAMPLE_INTERACTIVE_STEPS, errors)
    report_missing("visual_repeat_check DEFAULT_TARGETS", expected_visual_binaries - visual_binaries, errors)
    report_extra("visual_repeat_check DEFAULT_TARGETS", visual_binaries - expected_visual_binaries, errors)

    if errors:
        sys.stderr.write("example coverage check failed:\n")
        for error in errors:
            sys.stderr.write(f"  - {error}\n")
        return 1

    print(
        "checked example coverage: "
        f"{len(expected_binaries)} interactive example(s), "
        f"{len(expected_visual_binaries)} snapshot visual target(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
