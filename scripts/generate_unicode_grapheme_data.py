#!/usr/bin/env python3
"""Generate compact Unicode grapheme and terminal-width tables for Zit.

The normal test and release paths are network-free. Maintainers run this script
explicitly when updating the pinned Unicode version; downloads are verified
before generated source or conformance data is replaced.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path


UNICODE_VERSION = "17.0.0"


@dataclass(frozen=True)
class Source:
    filename: str
    url: str
    sha256: str


SOURCES = {
    "grapheme": Source(
        "GraphemeBreakProperty.txt",
        f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/auxiliary/GraphemeBreakProperty.txt",
        "d6b51d1d2ae5c33b451b7ed994b48f1f4dc62b2272a5831e7fd418514a6bae89",
    ),
    "test": Source(
        "GraphemeBreakTest.txt",
        f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/auxiliary/GraphemeBreakTest.txt",
        "e2d134d2c52919bace503ebb6a551c1855fe1a1faec18478c78fff254a1793ec",
    ),
    "derived": Source(
        "DerivedCoreProperties.txt",
        f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/DerivedCoreProperties.txt",
        "24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08",
    ),
    "east_asian_width": Source(
        "EastAsianWidth.txt",
        f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/EastAsianWidth.txt",
        "ea7ce50f3444a050333448dffef1cadd9325af55cbb764b4a2280faf52170a33",
    ),
    "emoji": Source(
        "emoji-data.txt",
        f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd/emoji/emoji-data.txt",
        "2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b",
    ),
    "license": Source(
        "UNICODE-LICENSE.txt",
        "https://www.unicode.org/license.txt",
        "e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96",
    ),
}


GCB_NAMES = {
    "CR": "cr",
    "LF": "lf",
    "Control": "control",
    "Extend": "extend",
    "ZWJ": "zwj",
    "Regional_Indicator": "regional_indicator",
    "Prepend": "prepend",
    "SpacingMark": "spacing_mark",
    "L": "hangul_l",
    "V": "hangul_v",
    "T": "hangul_t",
}

INCB_NAMES = {
    "Consonant": "consonant",
    "Extend": "extend",
    "Linker": "linker",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def read_source(source: Source, source_dir: Path | None) -> bytes:
    if source_dir is None:
        with urllib.request.urlopen(source.url, timeout=60) as response:
            data = response.read()
    else:
        data = (source_dir / source.filename).read_bytes()

    digest = hashlib.sha256(data).hexdigest()
    if digest != source.sha256:
        raise RuntimeError(
            f"{source.filename}: SHA-256 mismatch: expected {source.sha256}, got {digest}"
        )
    return data


def parse_codepoint_range(raw: str) -> tuple[int, int]:
    bounds = raw.strip().split("..", maxsplit=1)
    start = int(bounds[0], 16)
    end = int(bounds[1], 16) if len(bounds) == 2 else start
    return start, end


def merge_ranges(ranges: list[tuple[int, int, str]]) -> list[tuple[int, int, str]]:
    merged: list[tuple[int, int, str]] = []
    for start, end, value in sorted(ranges):
        if merged and merged[-1][2] == value and merged[-1][1] + 1 == start:
            previous = merged[-1]
            merged[-1] = (previous[0], end, value)
        else:
            merged.append((start, end, value))
    return merged


def parse_grapheme_ranges(data: bytes) -> list[tuple[int, int, str]]:
    ranges: list[tuple[int, int, str]] = []
    for line in data.decode("utf-8").splitlines():
        body = line.split("#", maxsplit=1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) != 2:
            continue
        value = GCB_NAMES.get(fields[1])
        if value is None:
            # Hangul LV/LVT are smaller and faster as an arithmetic lookup.
            if fields[1] in {"LV", "LVT"}:
                continue
            raise RuntimeError(f"unhandled Grapheme_Cluster_Break value: {fields[1]}")
        start, end = parse_codepoint_range(fields[0])
        ranges.append((start, end, value))
    return merge_ranges(ranges)


def parse_incb_ranges(data: bytes) -> list[tuple[int, int, str]]:
    ranges: list[tuple[int, int, str]] = []
    for line in data.decode("utf-8").splitlines():
        body = line.split("#", maxsplit=1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) != 3 or fields[1] != "InCB":
            continue
        value = INCB_NAMES.get(fields[2])
        if value is None:
            raise RuntimeError(f"unhandled Indic_Conjunct_Break value: {fields[2]}")
        start, end = parse_codepoint_range(fields[0])
        ranges.append((start, end, value))
    return merge_ranges(ranges)


def parse_binary_property(data: bytes, property_name: str) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int, str]] = []
    for line in data.decode("utf-8").splitlines():
        body = line.split("#", maxsplit=1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) != 2 or fields[1] != property_name:
            continue
        start, end = parse_codepoint_range(fields[0])
        ranges.append((start, end, property_name))
    return [(start, end) for start, end, _ in merge_ranges(ranges)]


def merge_binary_ranges(*groups: list[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for start, end in sorted(item for group in groups for item in group):
        if merged and start <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def hex_codepoint(value: int) -> str:
    return f"0x{value:04X}"


def render_value_ranges(
    name: str, ranges: list[tuple[int, int, str]], range_type: str
) -> list[str]:
    lines = [f"const {name} = [_]{range_type}{{"]
    for start, end, value in ranges:
        lines.append(
            f"    .{{ .start = {hex_codepoint(start)}, .end = {hex_codepoint(end)}, .value = .{value} }},"
        )
    lines.append("};")
    return lines


def render_binary_ranges(name: str, ranges: list[tuple[int, int]]) -> list[str]:
    lines = [f"const {name} = [_]Range{{"]
    for start, end in ranges:
        lines.append(
            f"    .{{ .start = {hex_codepoint(start)}, .end = {hex_codepoint(end)} }},"
        )
    lines.append("};")
    return lines


def render_zig(
    grapheme: list[tuple[int, int, str]],
    incb: list[tuple[int, int, str]],
    emoji: list[tuple[int, int]],
    emoji_presentation: list[tuple[int, int]],
    extended_pictographic: list[tuple[int, int]],
    east_asian_wide: list[tuple[int, int]],
) -> str:
    lines = [
        "// Generated by scripts/generate_unicode_grapheme_data.py; do not edit.",
        f'pub const unicode_version = "{UNICODE_VERSION}";',
        "",
        "pub const GraphemeClass = enum {",
        "    other,",
        "    cr,",
        "    lf,",
        "    control,",
        "    extend,",
        "    zwj,",
        "    regional_indicator,",
        "    prepend,",
        "    spacing_mark,",
        "    hangul_l,",
        "    hangul_v,",
        "    hangul_t,",
        "    hangul_lv,",
        "    hangul_lvt,",
        "};",
        "",
        "pub const IndicConjunctBreak = enum { none, consonant, extend, linker };",
        "",
        "const Range = struct { start: u21, end: u21 };",
        "const GraphemeRange = struct { start: u21, end: u21, value: GraphemeClass };",
        "const IndicRange = struct { start: u21, end: u21, value: IndicConjunctBreak };",
        "",
    ]
    lines.extend(render_value_ranges("grapheme_ranges", grapheme, "GraphemeRange"))
    lines.append("")
    lines.extend(render_value_ranges("indic_ranges", incb, "IndicRange"))
    lines.append("")
    lines.extend(render_binary_ranges("emoji_ranges", emoji))
    lines.append("")
    lines.extend(render_binary_ranges("emoji_presentation_ranges", emoji_presentation))
    lines.append("")
    lines.extend(render_binary_ranges("extended_pictographic_ranges", extended_pictographic))
    lines.append("")
    lines.extend(render_binary_ranges("east_asian_wide_ranges", east_asian_wide))
    lines.append("")
    lines.extend(
        render_binary_ranges(
            "terminal_wide_ranges",
            merge_binary_ranges(east_asian_wide, emoji_presentation),
        )
    )
    lines.extend(
        [
            "",
            "fn lookupValue(cp: u21, ranges: anytype, default_value: anytype) @TypeOf(default_value) {",
            "    var low: usize = 0;",
            "    var high: usize = ranges.len;",
            "    while (low < high) {",
            "        const mid = low + (high - low) / 2;",
            "        const range = ranges[mid];",
            "        if (cp < range.start) high = mid else if (cp > range.end) low = mid + 1 else return range.value;",
            "    }",
            "    return default_value;",
            "}",
            "",
            "fn contains(cp: u21, ranges: []const Range) bool {",
            "    var low: usize = 0;",
            "    var high: usize = ranges.len;",
            "    while (low < high) {",
            "        const mid = low + (high - low) / 2;",
            "        const range = ranges[mid];",
            "        if (cp < range.start) high = mid else if (cp > range.end) low = mid + 1 else return true;",
            "    }",
            "    return false;",
            "}",
            "",
            "pub fn graphemeClass(cp: u21) GraphemeClass {",
            "    if (cp >= 0xAC00 and cp <= 0xD7A3) return if ((cp - 0xAC00) % 28 == 0) .hangul_lv else .hangul_lvt;",
            "    return lookupValue(cp, &grapheme_ranges, GraphemeClass.other);",
            "}",
            "",
            "pub fn indicConjunctBreak(cp: u21) IndicConjunctBreak {",
            "    return lookupValue(cp, &indic_ranges, IndicConjunctBreak.none);",
            "}",
            "",
            "pub fn isEmoji(cp: u21) bool {",
            "    return contains(cp, &emoji_ranges);",
            "}",
            "",
            "pub fn isEmojiPresentation(cp: u21) bool {",
            "    return contains(cp, &emoji_presentation_ranges);",
            "}",
            "",
            "pub fn isExtendedPictographic(cp: u21) bool {",
            "    return contains(cp, &extended_pictographic_ranges);",
            "}",
            "",
            "pub fn isEastAsianWide(cp: u21) bool {",
            "    return contains(cp, &east_asian_wide_ranges);",
            "}",
            "",
            "pub fn isTerminalWide(cp: u21) bool {",
            "    return contains(cp, &terminal_wide_ranges);",
            "}",
            "",
        ]
    )
    return "\n".join(lines)


def write_if_changed(path: Path, data: bytes) -> None:
    if path.exists() and path.read_bytes() == data:
        print(f"unchanged {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"wrote {path}")


def main() -> int:
    root = repo_root()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, help="read verified source files locally")
    parser.add_argument(
        "--output",
        type=Path,
        default=root / "src/terminal/unicode_grapheme_data.zig",
    )
    parser.add_argument(
        "--test-output",
        type=Path,
        default=root / f"src/terminal/testdata/GraphemeBreakTest-{UNICODE_VERSION}.txt",
    )
    parser.add_argument(
        "--width-test-output",
        type=Path,
        default=root / f"src/terminal/testdata/EastAsianWidth-{UNICODE_VERSION}.txt",
    )
    parser.add_argument(
        "--license-output",
        type=Path,
        default=root / "src/terminal/testdata/UNICODE-LICENSE.txt",
    )
    args = parser.parse_args()

    loaded = {name: read_source(source, args.source_dir) for name, source in SOURCES.items()}
    generated = render_zig(
        parse_grapheme_ranges(loaded["grapheme"]),
        parse_incb_ranges(loaded["derived"]),
        parse_binary_property(loaded["emoji"], "Emoji"),
        parse_binary_property(loaded["emoji"], "Emoji_Presentation"),
        parse_binary_property(loaded["emoji"], "Extended_Pictographic"),
        merge_binary_ranges(
            parse_binary_property(loaded["east_asian_width"], "W"),
            parse_binary_property(loaded["east_asian_width"], "F"),
        ),
    ).encode("utf-8")

    write_if_changed(args.output, generated)
    write_if_changed(args.test_output, loaded["test"])
    write_if_changed(args.width_test_output, loaded["east_asian_width"])
    write_if_changed(args.license_output, loaded["license"])
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, urllib.error.URLError) as err:
        sys.stderr.write(f"error: {err}\n")
        raise SystemExit(1)
