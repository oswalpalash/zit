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
- CI must run `zig build release-check` on pull requests, `main` pushes, and release tags so the strongest public gate is not reserved for releases only.

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

- `zig build release-check`

`zig build release-check` is the authoritative aggregate gate. It runs the checks below and writes generated API docs under `zig-out/docs-release` plus visual captures under `zig-out/visual-repeat`.

- `zig build quality`
- `zig build contribution-gates`
- `zig fmt --check src/ examples/ build.zig`
- `zig build smoke`
- `zig build test`
- `zig build bench`
- `zig build-lib src/main.zig -femit-docs -fno-emit-bin`
- `zig build smoke -Dtarget=x86_64-linux`
- `zig build smoke -Dtarget=x86_64-windows`
- `python3 scripts/check_build_steps.py`
- `python3 scripts/check_build_steps.py --skip-interactive`
- `python3 scripts/check_debug_allocator_cleanup.py`
- `python3 scripts/check_ci_script_coverage.py`
- `python3 scripts/check_contribution_gates.py`
- `python3 scripts/check_widget_coverage.py`
- `python3 scripts/interactive_example_smoke.py`
- `python3 scripts/resize_smoke.py --no-build` to verify `input_test` receives a live PTY resize, every public interactive example survives the resize and quits cleanly, and live-size examples redraw at the new geometry.
- `python3 scripts/visual_repeat_check.py --count 4`
- Visually inspect the generated contact sheet for the real-world examples (`htop-clone`, `file-manager`, `text-editor`, `dashboard-demo`) and widget galleries (`widget-gallery`, `widget-gallery-extended`, `widget-gallery-layouts`) for alignment, hierarchy, spacing, clipped or overlapping text, and frame-to-frame drift.
- Review README, API docs, examples, and changelog for claims that exceed tested behavior.

Windows CI runs the public build-step checker with `--skip-interactive` because
GitHub's Windows shell does not provide the PTY semantics required by the TUI
run targets. Those same interactive targets remain covered on POSIX by
`check_build_steps.py`, `interactive_example_smoke.py`, `resize_smoke.py`, and
the repeated visual capture suite.
