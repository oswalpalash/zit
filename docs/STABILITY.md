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
- Benchmarks must enforce conservative budgets for render throughput, large-table scrolling, input decoding, and memory-retention optimizations.
- Keyboard accessibility, and mouse support where the widget exposes pointer behavior.
- Terminal mouse protocol coordinates must be normalized at the input boundary so widget hit tests use the same zero-based coordinate system as rendering and layout.
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
- `zig build bench` must fail when conservative performance budgets are exceeded; the budgets are intentionally loose enough for CI variance but tight enough to catch algorithmic regressions.
- `zig build-lib src/main.zig -femit-docs -fno-emit-bin`
- `zig build smoke -Dtarget=x86_64-linux`
- `zig build smoke -Dtarget=x86_64-windows`
- `python3 scripts/check_build_steps.py`
- `python3 scripts/check_build_steps.py --skip-interactive`
- `python3 scripts/check_debug_allocator_cleanup.py`
- `python3 scripts/check_ci_script_coverage.py`
- `python3 scripts/check_contribution_gates.py`
- `python3 scripts/check_accessibility_metadata.py` to require every public widget export to expose semantic accessibility metadata for focus announcements and assistive integrations.
- `python3 scripts/check_application_input_binding.py`
- `python3 scripts/check_example_coverage.py`
- `python3 scripts/check_interactive_alt_screen.py`
- `python3 scripts/check_owned_allocation_patterns.py`
- `python3 scripts/check_terminal_state_cleanup.py`
- `python3 scripts/check_unreachable_catches.py`
- `python3 scripts/check_widget_coverage.py`
- `python3 scripts/check_widget_owner_casts.py`
- `python3 scripts/interactive_example_smoke.py`
- `python3 scripts/resize_smoke.py --no-build` to verify `input_test` receives live PTY resize events, every public interactive example survives rapid tiny-size stress down to 1x1, redraws a visible `resize: WxH` marker at the final geometry, and quits cleanly.
- `python3 scripts/mouse_alignment_smoke.py --no-build` to verify real SGR mouse input maps terminal 1-based coordinates to Zit screen coordinates and clicks the rendered demo button only at its actual row.
- `InputHandler.pollEvent` and `decodeEventFromBytes` are the input boundary for terminal mouse normalization: returned mouse events must already be zero-based and aligned with renderer/widget layout rects, numeric CSI/SGR parameters and legacy X10/normal tracking bytes must be validated before arithmetic, `translateMouseCoordinates` must remain idempotent for those events, and raw terminal coordinates must use `translateTerminalMouseCoordinates`.
- `python3 scripts/check_mouse_hit_coverage.py` to require every public mouse-capable widget to declare direct hit-test coverage before release.
- `python3 scripts/visual_repeat_check.py --count 4`
- Visually inspect the generated contact sheet for the real-world examples (`htop-clone`, `file-manager`, `text-editor`, `dashboard-demo`) and widget galleries (`widget-gallery`, `widget-gallery-extended`, `widget-gallery-layouts`) for alignment, hierarchy, spacing, clipped or overlapping text, and frame-to-frame drift.
- `python3 scripts/check_application_input_binding.py` requires examples that initialize `Application` and `InputHandler` together to route polling through `Application.bindInput` / `pollInputOnce`.
- `python3 scripts/check_example_coverage.py` keeps the build target list, interactive PTY smoke manifest, public build-step classification, and repeated visual target manifest in sync.
- `python3 scripts/check_interactive_alt_screen.py` requires every interactive example to enter and exit the alternate screen so rendered rows and terminal mouse coordinates share a stable viewport origin.
- `python3 scripts/check_owned_allocation_patterns.py` rejects non-transactional owned-string append and replacement patterns so allocator failures preserve existing widget state.
- `python3 scripts/check_terminal_state_cleanup.py` requires interactive examples to restore raw mode, mouse tracking, cursor visibility, and alternate-screen state they enable.
- `python3 scripts/check_unreachable_catches.py` rejects `catch unreachable` so recoverable errors are propagated or handled instead of becoming panics.
- Review README, API docs, examples, and changelog for claims that exceed tested behavior.

Hosted CI runs the matrix public build-step checker with `--skip-interactive`
because GitHub shell runners do not provide consistent PTY semantics for TUI
run targets across operating systems. Those same interactive targets remain
covered by dedicated PTY jobs: `interactive_example_smoke.py`,
`resize_smoke.py`, `mouse_alignment_smoke.py`, and the repeated visual capture
suite.
