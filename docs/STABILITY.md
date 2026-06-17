# Stability Policy

Zit is governed by four tenets, in priority order:

1. Efficiency
2. Reliability
3. Stability
4. Features

Features are welcome only when they preserve the first three tenets.

## Zig Baseline

- Supported compiler line: Zig 0.16.x.
- `build.zig.zon` is the source of truth for the minimum supported compiler.
- CI must compile and test on Linux, macOS, and Windows before a release tag is cut.

## Public API

- Stable public modules are `terminal`, `input`, `render`, `layout`, `event`, `widget`, `memory`, `testing`, `i18n`, and `quickstart`.
- Breaking changes are allowed before 1.0 only when they harden ownership, lifecycle, error handling, portability, or API consistency.
- Every breaking change needs a changelog entry and migration note.
- Experimental or incomplete APIs must be documented as such before being promoted in README examples.

## Reliability Bar

Before a feature is promoted as stable, it needs:

- Allocator-aware `init`/`deinit` behavior with clear ownership rules.
- Interactive examples must exit without `DebugAllocator` diagnostics, panic output, or mismatched allocation/free sizes.
- Tests for lifecycle, bounds, zero-size layout, resize behavior, and error paths.
- Snapshot coverage when rendering output is user-visible.
- Keyboard accessibility, and mouse support where the widget exposes pointer behavior.
- No unexpected panics for user input, terminal size changes, or normal rendering paths.

## Release Checklist

- `zig build quality`
- `zig fmt --check src/ examples/ build.zig`
- `zig build smoke`
- `zig build test`
- `zig build bench`
- `zig build-lib src/main.zig -femit-docs -fno-emit-bin`
- `zig build smoke -Dtarget=x86_64-linux`
- `zig build smoke -Dtarget=x86_64-windows`
- `python3 scripts/check_build_steps.py`
- `python3 scripts/check_debug_allocator_cleanup.py`
- `python3 scripts/check_widget_coverage.py`
- `python3 scripts/interactive_example_smoke.py`
- `python3 scripts/visual_repeat_check.py --count 4`
- Visually inspect the generated contact sheet for the real-world examples (`htop-clone`, `file-manager`, `text-editor`, `dashboard-demo`) and widget galleries (`widget-gallery`, `widget-gallery-extended`, `widget-gallery-layouts`) for alignment, hierarchy, spacing, clipped or overlapping text, and frame-to-frame drift.
- Review README, API docs, examples, and changelog for claims that exceed tested behavior.
