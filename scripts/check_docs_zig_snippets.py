#!/usr/bin/env python3
"""Validate public Markdown Zig snippets model current, lifecycle-safe APIs."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


PUBLIC_MARKDOWN_ROOTS = (
    Path("README.md"),
    Path("CONTRIBUTING.md"),
    Path("STYLE_GUIDE.md"),
    Path("docs"),
    Path("examples/README.md"),
    Path(".github/PULL_REQUEST_TEMPLATE.md"),
)

FENCE_START = re.compile(r"^```([A-Za-z0-9_-]*)\s*$")
EMPTY_CATCH = re.compile(r"\bcatch\s*\{\s*\}")
UNREACHABLE_CATCH = re.compile(r"\bcatch\s+unreachable\b")
PANIC = re.compile(r"@panic\s*\(")
STANDALONE_UNREACHABLE = re.compile(r"(^|[;{\s])unreachable\s*;")
DIRECT_WIDGET_STATE = re.compile(
    r"(?:\b(?:[A-Za-z_][A-Za-z0-9_]*\.)*widget|\]\s*\.\s*\*)\.(?:focused|enabled|visible)\s*=",
)
DIRECT_WIDGET_PARENT = re.compile(
    r"(?:\b(?:[A-Za-z_][A-Za-z0-9_]*\.)*widget|\]\s*\.\s*\*)\.parent\s*=(?!=)",
)
DIRECT_TREE_EXPANSION = re.compile(
    r"\b[A-Za-z_][A-Za-z0-9_]*\.nodes\.items\[[^\]\n]+\]\.expanded\s*=",
)
PUBLIC_DECL = re.compile(r"(?m)^pub\s+(?:const|fn|var)\s+([A-Za-z_][A-Za-z0-9_]*)\b")
ROOT_MODULE = re.compile(
    r'(?m)^pub\s+const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*@import\("([^"]+)"\);',
)
PUBLIC_API_REF = re.compile(
    r"\bzit\.([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)",
)


@dataclass(frozen=True)
class Snippet:
    path: Path
    start_line: int
    text: str


@dataclass(frozen=True)
class PublicApi:
    root_exports: frozenset[str]
    module_exports: dict[str, frozenset[str]]


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def markdown_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for rel in PUBLIC_MARKDOWN_ROOTS:
        path = root / rel
        if path.is_dir():
            files.extend(sorted(path.glob("*.md")))
        elif path.exists():
            files.append(path)
    return sorted(set(files))


def zig_snippets(path: Path, root: Path) -> list[Snippet]:
    snippets: list[Snippet] = []
    in_zig = False
    start_line = 0
    lines: list[str] = []

    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        fence = FENCE_START.match(line)
        if fence:
            if in_zig:
                snippets.append(Snippet(path.relative_to(root), start_line, "\n".join(lines)))
                in_zig = False
                lines = []
            else:
                in_zig = fence.group(1).lower() == "zig"
                start_line = number + 1
                lines = []
            continue

        if in_zig:
            lines.append(line)

    return snippets


def snippet_line(snippet: Snippet, index: int) -> int:
    return snippet.start_line + snippet.text.count("\n", 0, index)


def load_public_api(root: Path) -> PublicApi:
    main_path = root / "src/main.zig"
    main_text = main_path.read_text(encoding="utf-8")
    root_exports = frozenset(PUBLIC_DECL.findall(main_text))
    module_exports: dict[str, frozenset[str]] = {}

    for match in ROOT_MODULE.finditer(main_text):
        module_name, import_path = match.groups()
        source_path = main_path.parent / import_path
        if not source_path.is_file():
            raise RuntimeError(f"src/main.zig imports missing public module {import_path}")
        module_exports[module_name] = frozenset(
            PUBLIC_DECL.findall(source_path.read_text(encoding="utf-8"))
        )

    return PublicApi(root_exports, module_exports)


def validate_snippet(snippet: Snippet, public_api: PublicApi) -> list[str]:
    failures: list[str] = []
    checks = (
        (EMPTY_CATCH, "empty `catch {}` blocks hide recoverable errors in public Zig snippets"),
        (UNREACHABLE_CATCH, "`catch unreachable` turns recoverable errors into panics in public Zig snippets"),
        (PANIC, "`@panic` should not appear in public Zig snippets"),
        (STANDALONE_UNREACHABLE, "`unreachable` should not appear in public Zig snippets"),
    )
    for pattern, message in checks:
        for match in pattern.finditer(snippet.text):
            failures.append(f"{snippet.path}:{snippet_line(snippet, match.start())}: {message}")

    if "std.heap.DebugAllocator" in snippet.text and "std.debug.assert" not in snippet.text:
        failures.append(f"{snippet.path}:{snippet.start_line}: DebugAllocator snippets must assert clean `deinit()`")

    lifecycle_checks = (
        (DIRECT_WIDGET_STATE, "use Widget.setFocus(), setEnabled(), or setVisible() so lifecycle hooks run"),
        (DIRECT_WIDGET_PARENT, "use Widget.attachTo() or detachFrom() so parent ownership is checked"),
        (DIRECT_TREE_EXPANSION, "use TreeView.setExpanded() so visible-cache and dirty state stay synchronized"),
    )
    for pattern, message in lifecycle_checks:
        for match in pattern.finditer(snippet.text):
            failures.append(f"{snippet.path}:{snippet_line(snippet, match.start())}: {message}")

    for match in PUBLIC_API_REF.finditer(snippet.text):
        module_name, symbol_name = match.groups()
        if module_name not in public_api.root_exports:
            failures.append(
                f"{snippet.path}:{snippet_line(snippet, match.start())}: "
                f"`zit.{module_name}` is not exported by src/main.zig"
            )
            continue
        exports = public_api.module_exports.get(module_name)
        if exports is not None and symbol_name not in exports:
            failures.append(
                f"{snippet.path}:{snippet_line(snippet, match.start())}: "
                f"`zit.{module_name}.{symbol_name}` is not a public declaration"
            )

    return failures


def run_self_tests() -> None:
    public_api = PublicApi(
        root_exports=frozenset({"widget"}),
        module_exports={"widget": frozenset({"InputField", "Widget"})},
    )
    invalid = Snippet(
        Path("docs/example.md"),
        10,
        "const field: zit.widget.Input = undefined;\n"
        "field.widget.focused = true;\n"
        "field.widget.parent = owner;\n"
        "tree.nodes.items[0].expanded = true;\n"
        "const stale = zit.missing.Widget;",
    )
    failures = validate_snippet(invalid, public_api)
    if not any("zit.widget.Input" in failure for failure in failures):
        raise AssertionError("stale public API reference was not detected")
    if not any("setFocus" in failure for failure in failures):
        raise AssertionError("direct widget lifecycle mutation was not detected")
    if not any("attachTo" in failure for failure in failures):
        raise AssertionError("direct widget parent mutation was not detected")
    if not any("setExpanded" in failure for failure in failures):
        raise AssertionError("direct TreeView expansion was not detected")
    if not any("zit.missing" in failure for failure in failures):
        raise AssertionError("stale root module reference was not detected")

    valid = Snippet(
        Path("docs/example.md"),
        20,
        "const field: *zit.widget.InputField = undefined;\nfield.widget.setFocus(true);",
    )
    if validate_snippet(valid, public_api):
        raise AssertionError("valid public API usage was rejected")


def main() -> int:
    root = repo_root()
    run_self_tests()
    public_api = load_public_api(root)
    snippets: list[Snippet] = []
    for path in markdown_files(root):
        snippets.extend(zig_snippets(path, root))

    failures: list[str] = []
    for snippet in snippets:
        failures.extend(validate_snippet(snippet, public_api))

    if failures:
        sys.stderr.write("public Markdown Zig snippets must model current, lifecycle-safe APIs:\n")
        for failure in failures:
            sys.stderr.write(f"  - {failure}\n")
        return 1

    reference_count = sum(len(PUBLIC_API_REF.findall(snippet.text)) for snippet in snippets)
    print(
        f"checked {len(snippets)} public Markdown Zig snippet(s) and "
        f"{reference_count} direct public API reference(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
