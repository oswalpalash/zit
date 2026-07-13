# Unicode Grapheme Test Data

These checked-in files keep normal builds and tests deterministic and offline:

- `GraphemeBreakTest-17.0.0.txt` is the official Unicode 17 extended grapheme cluster conformance fixture.
- `EastAsianWidth-17.0.0.txt` is the official Unicode 17 East Asian Width property data used to exhaustively verify the generated width lookup.
- `UNICODE-LICENSE.txt` is the Unicode data license distributed with the fixture and generated property data.

Regenerate the fixture and `src/terminal/unicode_grapheme_data.zig` with:

```sh
python3 scripts/generate_unicode_grapheme_data.py
```

The generator downloads and verifies these pinned inputs:

| Input | SHA-256 |
| --- | --- |
| `https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakProperty.txt` | `d6b51d1d2ae5c33b451b7ed994b48f1f4dc62b2272a5831e7fd418514a6bae89` |
| `https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakTest.txt` | `e2d134d2c52919bace503ebb6a551c1855fe1a1faec18478c78fff254a1793ec` |
| `https://www.unicode.org/Public/17.0.0/ucd/DerivedCoreProperties.txt` | `24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08` |
| `https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt` | `ea7ce50f3444a050333448dffef1cadd9325af55cbb764b4a2280faf52170a33` |
| `https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt` | `2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b` |
| `https://www.unicode.org/license.txt` | `e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96` |

The generated Zig file records the same Unicode version. Tests fail if the generated version and fixture headers diverge, and compare the East Asian `W/F` lookup against the official property for every Unicode codepoint.
